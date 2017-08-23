class Class
  def descendants
    ObjectSpace.each_object(::Class).select {|klass| klass < self }
  end
end

# Patch for Telegram bot client so ctrl+c works
module Telegram
  module Bot
    class Client
      def listen(&block)
        logger.info('Starting bot')
        running = true
        # Signal.trap('INT') { running = false }
        fetch_updates(&block) while running
        exit
      end
    end
  end
end

# hash: a ruby Hash
# whitelist: array of keys to allow in the return hash
def filter_keys(hash, whitelist)
  out = {}
  hash.keys.each do |k|
    if whitelist.include?(k)
      out[k] = hash[k]
    end
  end
  out
end
