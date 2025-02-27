#!ruby -Ku
# -*- coding: utf-8; -*-

# path setting
this_file_s_path = File.expand_path(File.dirname(__FILE__))
twym_path = File.expand_path(this_file_s_path + "/")
$LOAD_PATH.unshift twym_path
$LOAD_PATH.unshift this_file_s_path

require 'socket'
require 'nkf'
require 'pp'
#require 'rubygems'
#require 'ruby-debug'

# ruby1.9はUTF-32BEを扱うのに標準ライブラリ kconv を使う
#require 'kconv'

class QC_ports
  attr_accessor :id, :name, :line1, :line2, :line3, :line4, :time, :display_second, :display_second_for_qc, :display_second_port
  DisplayTimeBuffer = 1 #sec
  def initialize(id, name_port, line1_port, line2_port, line3_port, line4_port, display_second_port)
    @id = id
    @name = name_port
    @line1 = line1_port
    @line2 = line2_port
    @line3 = line3_port
    @line4 = line4_port
    @display_second_port = display_second_port
    @time = nil # 前回送信した時刻
    set_display_second 7
  end

  def set_display_second(sec)
    @display_second_for_qc = sec
    @display_second = @display_second_for_qc + DisplayTimeBuffer
  end
end

class Message
  attr_accessor :name
  attr_reader :line1, :line2, :line3, :line4, :org_str

  def initialize(name, str)
    @name     = name
    @org_str  = str.clone
    @work_str = str
    init_lines
  end

  def split_to_lines(size)
    return ' ' unless @work_str # 空文字列送信するとQC側で前の文字列が残っちゃうので space 送る
    str = @work_str.slice! /\A(.{#{size}})/
    unless str #全文字処理完了
      str = @work_str
      @work_str = nil
    end
    str = ' ' if str == '' #上記の理由で空文字送信防止
    str
  end

  def init_lines
    @line1 = split_to_lines(20) #文字数
    @line2 = split_to_lines(40)
    @line3 = split_to_lines(40)
    @line4 = split_to_lines(40)
  end

end

class ToQC
  attr_accessor :display_second
  public
  def initialize
    @address = '225.0.0.0'
    @ports = []
    @ports << QC_ports.new(1, 50100, 50101, 50102, 50103, 50104, 50110)
    @ports << QC_ports.new(2, 50200, 50201, 50202, 50203, 50204, 50210)
    @ports << QC_ports.new(3, 50300, 50301, 50302, 50303, 50304, 50310)
    @port_star =  51001
    @display_second = 10
    @queue = Array.new
  end

  def queue_empty?
    @queue.empty?
  end

  # 未表示文を押し出したいときは引数なしで呼び出し
  # 戻り値 true: 全部表示できました
  #   false: いっぱいで待ち状態です
  def send(name = nil, str = nil)
    @queue.push Message.new(name, str) unless name == nil # 一度queueにいれる
    return true if @queue.empty?
    message = @queue.shift # queue 先頭から取り出し
    result = send_message(message, @display_second)
    if result == false
      @queue.unshift message # queue の先頭に戻す
      return false # まだ表示したいのだけど、空き無し
    end
    send unless @queue.empty? # もっと表示できるかもの自己問い合わせ
    return true # 全部表示できた
  end

  private

  # 前の送信から指定秒秒経過したportがあれば送信
  def send_message(message, display_second)
    @ports.each do | port |  
      if port.time == nil || port.time < Time.now - port.display_second
        port.set_display_second display_second
        send_message_every_ports(port, message)
        return true
      end
    end
    return false # 送信できなかったので差し戻し
  end

  def send_message_every_ports(port, message)
    pp message
    send_star(message.org_str)               # star
    send_UDP(message.name,  port.name)   # メッセージ name
    send_UDP(message.line1, port.line1)  # メッセージ 1行目
    send_UDP(message.line2, port.line2)  # メッセージ 2行目
    send_UDP(message.line3, port.line3)  # メッセージ 3行目
    send_UDP(message.line4, port.line4)  # メッセージ 4行目
    send_UDP(port.display_second_for_qc.to_s, port.display_second_port)  # 何秒表示するか
    port.time = Time.now
  end
  
  def send_star(str)
    str_u8 = NKF.nkf('--utf8', str) # out:UTF8(non BOM)
    if str_u8 =~ /\*/ui or str_u8 =~ /★/u or str_u8 =~ /☆/u # u: UTF-8, i: 大文字小文字無視
      send_UDP("star", @port_star)
   end
  end

  def send_UDP(str_u8, port)
    # 改行コード除去
    str_u8.gsub! /\r/,'' # 日本語文字列にchopを使うとエラーになるので gsubで
    str_u8.gsub! /\n/,''

    socket = UDPSocket.open()
    socket.connect(@address, port)
    p "#{port}: #{str_u8}"

    # nkf
    str_u32BE = NKF.nkf('-w32B0 -W',str_u8) # out: UTF-32(non BOM), in: UTF-8(non BOM)
    #ruby1.9.1
    #  str_u32BE = Kconv.kconv(str_u8,  Kconv::UTF32,  Kconv::UTF8)
    
    socket.send(str_u32BE, 0)
  end
end

