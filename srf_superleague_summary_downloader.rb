require 'net/http'
require 'byebug'
require 'fileutils'
require 'json'
require 'ox'

require 'active_support'
require 'active_support/core_ext/string/inflections'

ROUND_MIN = 160
URN_REGEX = %r{urn:srf:ais:video:([a-f0-9\-]{36})}
INTEGRATIONLAYER_BASE_URL = 'http://il.srgssr.ch/integrationlayer/1.0/ue/srf/video/play'
SRF_PLAY_BASE_URL = 'http://www.srf.ch/play/tv/sportaktuell/video/something-or-other'
EXTENSION = '.mp4'

YEAR_PHASE_ID_MAP = {
  2016 => 2496,
  2017 => 3195,
  2018 => 3408
}

def info(string)
  puts "===> #{string} <==="
end

def swisstxt_api_url(year, round)
  phase_id = YEAR_PHASE_ID_MAP[year]

  raise "No phase id for year #{year}. Look up phase id in AJAX requests on http://www.srf.ch/sport/resultcenter/results#football/super-league" unless phase_id

  "http://sport.api.swisstxt.ch/v1/eventItems?phaseIds=#{phase_id}-171-#{round + ROUND_MIN - 1}&lang=de"
end

def fetch_summary_ids(year, round)
  round_api_url = swisstxt_api_url(year, round)

  info "Fetching #{round_api_url}"
  uri = URI.parse(round_api_url)
  swisstxt_json = Net::HTTP.get(uri)
  parsed = JSON.parse(swisstxt_json)

  scores = parsed.map { |game| game['scores']['main']['formatted'] }
  ids = parsed.map { |game| game['videoAssetId'] }

  [ids, scores]
end

def fetch_summary_meta_information(summary_id, score)
  integrationlayer_xml_url = "#{INTEGRATIONLAYER_BASE_URL}/#{summary_id}.xml"
  info "Fetching #{integrationlayer_xml_url}"

  uri = URI.parse(integrationlayer_xml_url)
  integrationlayer_xml_response = Net::HTTP.get_response(uri)
  integrationlayer_xml = integrationlayer_xml_response.body

  if integrationlayer_xml_response.code == '203'
    begin
      integrationlayer_document = Ox.load(integrationlayer_xml)
    rescue Ox::ParseError => e
      puts e.message
      puts integrationlayer_xml
    end
  else
    puts 'Error fetching integration layer xml:'
    p integrationlayer_xml_response
  end

  title = integrationlayer_document.locate('Video/AssetMetadatas/AssetMetadata/title').first.text
  asset_id = integrationlayer_document.locate('Video/AssetSet/Assets/Video/id').first.text
  mark_in = integrationlayer_document.locate('Video/markIn').first.text.to_i / 1000.0
  duration = integrationlayer_document.locate('Video/duration').first.text.to_i / 1000.0

  meta_info = {
    title: "#{title} #{score}",
    asset_id: asset_id,
    mark_in: mark_in,
    duration: duration
  }

  info "Extracted meta info: #{meta_info.inspect}"

  meta_info
end

def download_asset(asset_id, round_directory)
  youtube_dl_command = [
    'youtube-dl',
    "#{SRF_PLAY_BASE_URL}?id=#{asset_id}",
    '-o', File.join(round_directory, "#{asset_id}.%(ext)s")
  ]

  info "Executing #{youtube_dl_command.join ' '}"
  success = system *youtube_dl_command

  raise 'Command failed' unless success
end

def reencode_asset_to_summary(meta_info, round_directory)
  asset_path = File.join(round_directory, "#{meta_info[:asset_id]}#{EXTENSION}")
  destination_path = File.join(round_directory, "#{meta_info[:title].parameterize}#{EXTENSION}")

  ffmpeg_command = [
    'ffmpeg',
    '-y', # overwrite without asking
    '-i', asset_path,
    '-bsf:a', 'aac_adtstoasc',
    '-ss', meta_info[:mark_in].to_s,
    '-c', 'copy',
    '-t', meta_info[:duration].to_s,
    destination_path
  ]

  info "Executing #{ffmpeg_command.join ' '}"
  success = system *ffmpeg_command

  raise 'Command failed' unless success
end

def download_summaries(year, round)
  summary_ids, scores = fetch_summary_ids(year, round)
  info "Found summary ids: #{summary_ids.inspect}"

  round_directory = File.join('data', year.to_s, round.to_s)
  FileUtils.mkdir_p(round_directory) unless File.exist?(round_directory)

  meta_infos = {}
  summary_ids.each_with_index do |summary_id, i|
    next unless summary_id
    meta_infos[summary_id] = fetch_summary_meta_information(summary_id, scores[i])
  end

  asset_ids = meta_infos.map { |k, v| v[:asset_id] }

  asset_ids.uniq!
  info "Found #{asset_ids.count} assets to download"

  asset_ids.each do |asset_id|
    download_asset(asset_id, round_directory)
  end

  meta_infos.each do |id, meta_info|
    reencode_asset_to_summary(meta_info, round_directory)
  end

  meta_infos.each do |id, meta_info|
    FileUtils.rm_rf File.join(round_directory, "#{meta_info[:asset_id]}#{EXTENSION}")
  end
end

download_summaries(ARGV[0].to_i, ARGV[1].to_i)
