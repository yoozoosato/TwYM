#! ruby -Ku
# -*- coding: utf-8; -*-
$:.unshift File.join(File.dirname(__FILE__))

require 'net/http'
require 'uri'
require 'drb'

#gems
require 'rubygems'
require 'json'
require 'oauth'
require "twitter/json_stream"
require "eventmachine"

# TwYM
require 'twitter_oauth_authorize.rb'
require 'config.rb'

# twitter query
#HASHTAG = 'kosenconf'
#HASHTAG = 'glt'
HASHTAG = 'nowplaying'
# 引数指定があればそちら優先、なければ HASHTAG
query = URI.encode( ARGV.shift || HASHTAG )

# for OAuth
OAuthAuthorizer.run unless (File.exist?(TWITTER_OAUTH_CONFIG_FILE)) #初回時
at = JSON.parse(File.read(TWITTER_OAUTH_CONFIG_FILE))
oauth_access_token  = at['token']
oauth_access_secret = at['secret']

# tuple space
$ts = DRbObject.new_with_uri(TS_URL)

EventMachine::run {
  EventMachine::defer {
    stream = Twitter::JSONStream.connect(
               :ssl => true,
               :port => 443,
               :path => "/1/statuses/filter.json?track=#{query}",
               :oauth => {
                 :consumer_key    => TWITTER_OAUTH_CONSUMER_KEY,
                 :consumer_secret => TWITTER_OAUTH_CONSUMER_SECRET,
                 :access_key      => oauth_access_token,
                 :access_secret   => oauth_access_secret })
    stream.each_item do |status|
      tweet = JSON.parse(status)      
      screen_name = tweet['user']['screen_name']
      body = tweet['text'].gsub(/##{query}$/i,'')
      puts "#{screen_name}: #{body}"
      mb = { NICK => screen_name, MESSAGE => body }
      $ts.write([TWITTER, mb], TUPLE_AVAILAVLE_TIME)
    end
  }
}
