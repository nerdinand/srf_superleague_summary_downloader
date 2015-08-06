# SRF Super League Summary Downloader
A script to download SRF Super League summary videos

This is a simple script that will download SRF Super League summary videos from srf.ch for you. 
It works by scraping the the website where the videos are linked from, e.g. 
http://www.srf.ch/sport/resultate/fussball/super-league and then downloads those videos via 
[youtube-dl](http://rg3.github.io/youtube-dl/) and processes them with [ffmpeg](http://ffmpeg.org/).

## Prerequisites

The script needs `youtube-dl` and `ffmpeg` installed in order to work. On a Mac, simply run this to 
install (if you have Homebrew, which you should):
```
brew install youtube-dl ffmpeg
```

To run the script, you'll need Ruby too, comes preinstalled on a Mac.

## Running the script

Simply run the script with
```
ruby srf_superleague_summary_downloader.rb <year> <round>
```

For example
```
ruby srf_superleague_summary_downloader.rb 2016 1
```
will download summaries for the round 1 (of 36) of year 2016.
