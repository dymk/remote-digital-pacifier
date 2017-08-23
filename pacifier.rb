require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require File.join(Dir.pwd, 'auth_config.rb')
require_relative 'misc.rb'
require 'pry'

Telegram::Bot.configure do |config|
  config.adapter = :excon
end

ActiveRecord::Base.configurations = YAML::load(IO.read("db/config.yml"))
ActiveRecord::Base.establish_connection ActiveRecord::Base.configurations['development']

puts "booting #{bot_name}..."

IKB = Telegram::Bot::Types::InlineKeyboardButton
IKM = Telegram::Bot::Types::InlineKeyboardMarkup

def list_commands(bot, message)
  kb = [
    IKB.new(text: 'Play sound', callback_data: 'list_sounds')
  ]
  markup = IKM.new(inline_keyboard: kb)
  bot.api.send_message(
    chat_id: from_id_for_message(message),
    text: 'Make a choice', 
    reply_markup: markup
  )
end

def list_sounds(bot, message)
  kb = get_file_list.each_with_index.map do |file_name, idx|
    IKB.new(text: file_name, callback_data: "play_sound #{idx}")
  end
  markup = IKM.new(inline_keyboard: kb)
  bot.api.send_message(
    chat_id: from_id_for_message(message),
    text: 'Choose a sound',
    reply_markup: markup
  )
end

def remove_kb 
  Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
end

def play_sound(bot, message, idx)
  puts "going to play sound at idx: #{idx}"

  idx = idx.to_i
  file = get_file_list()[idx]

  if !file
    bot.api.send_message(
      chat_id: from_id_for_message(message),
      text: 'Unable to find that sound!',
      reply_markup: remove_kb
    )
    list_sounds(bot, message)
  else
    file_info = get_file_info(file)
    base_msg = "playing #{file} (#{file_info[:duration]} seconds)"
    sent_message = bot.api.send_message(
      chat_id: from_id_for_message(message),
      text: base_msg,
      # reply_markup: remove_kb
    )

    t2 = Thread.new do 
      `mpv #{file}`
    end

    counter = 0
    while t2.alive?
      counter = counter + 1
      sleep 1
      bot.api.edit_message_text(
        chat_id: from_id_for_message(message),
        message_id: sent_message["result"]["message_id"],
        text: base_msg + ("." * counter)
      )
    end

    bot.api.send_message(
      chat_id: from_id_for_message(message),
      text: "done!",
      reply_markup: remove_kb
    )
    list_commands(bot, message)
  end
end

def get_file_list
  Dir['sounds/*.{ogg,mp3}']
end

puts "sound files: #{get_file_list.inspect}"

def get_file_info(fname)
  text = `mediainfo #{fname}`
  ret = {}
  ret[:duration] = 0
  if m = /Duration\s+:\s+(\d+)\ss/.match(text)
    ret[:duration] = m[1].to_i
  end

  ret
end

def handle_callback(bot, message)
  cmd, params = message.data.split(' ')
  case cmd
  when 'play_sound' then play_sound(bot, message, *params)
  when 'list_sounds' then list_sounds(bot, message)
  else 
    bot.api.send_message(
      chat_id: from_id_for_message(message), 
      text: "unknown: #{cmd.inspect}(#{params.inspect})"
    )
  end
end

def handle_message(bot, message)
  case message.text
  when "/help", "/start" then list_commands(bot, message)
  when "/listsounds" then list_sounds(bot, message)
  else list_commands(bot, message)
  end
end

def from_id_for_message(message)
  case message
  when Telegram::Bot::Types::CallbackQuery then message.from.id
  when Telegram::Bot::Types::Message then message.chat.id
  end
end

Telegram::Bot::Client.run(api_key) do |bot|
  puts "listening.."
  bot.listen do |message|
    puts "got message: #{message}"
    from_id = from_id_for_message(message)
    if !from_id
      puts "no chat set, skipping"
      next
    end
    if from_id != admin_telegram_channel
      puts "from unknown channel #{message.chat.id}, skipping"
      next
    end

    case message
    when Telegram::Bot::Types::CallbackQuery then handle_callback(bot, message)
    when Telegram::Bot::Types::Message then handle_message(bot, message)
    end
  end
end
