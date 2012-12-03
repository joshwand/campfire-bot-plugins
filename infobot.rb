require 'yaml'

class Infobot < CampfireBot::Plugin
  
  Infobot::DEFINE_REGEXP = /(no, )*(.+) is ([^\?]+)(?!\?)$/
  Infobot::RESPOND_REGEXP = /(what's|what is|who is|who's|where|where's|how's|how is) ([^\?]+)(?=\?)*/
  
  # if BOT_ENVIRONMENT == 'development'
    on_message Regexp.new("^#{bot.config['nickname']},\\s+#{RESPOND_REGEXP.source}", Regexp::IGNORECASE), :respond
    on_message Regexp.new("^#{bot.config['nickname']},\\s+#{DEFINE_REGEXP.source}", Regexp::IGNORECASE), :define
    on_command 'reload_facts', :reload
  # end
  
  def initialize
    @log = Logging.logger["CampfireBot::Plugin::Infobot"]
    @bot_root = bot.config['bot_root'].nil? ? "/opt/campfire-bot" : \
        bot.config['bot_root']
    # @log.debug "entering initialize()"
    
  end
  
  def respond(msg)
    # @log.debug "entering respond()"
    @facts = init()
    @log.debug msg[:message]
    @log.debug msg[:message] =~ RESPOND_REGEXP # Regexp.new("^#{Bot.instance.config['nickname']},\\s+#{RESPOND_REGEXP.source}", Regexp::IGNORECASE)
    @log.debug "1, 2, 3: #{$1}, #{$2}, #{$3}"
    @log.info "Checking for fact: got #{@facts.keys.count} of them"
    if !@facts.has_key?($2.downcase)
      msg.speak("Sorry, I don't know what #{$2} is.")
    else
      fact = @facts[$2.downcase]
      msg.speak("#{msg[:person].split(" ")[0]}, #{$2} is #{fact}.")
    end
  end
  
  def define(msg)
    @log.debug 'entering define()'
    @facts = init()
    @log.debug PP.singleline_pp(@facts, '')
    @log.debug msg[:message]
    @log.debug msg[:message] =~ Regexp.new("^#{bot.config['nickname']},\\s+#{DEFINE_REGEXP.source}",
        Regexp::IGNORECASE)
    @log.debug "1, 2, 3, 4: #{$1}, #{$2}, #{$3}, #{$4}"
    @facts[$2.downcase] = $3
    msg.speak("Okay, #{$2} is now #{$3}")
    File.open(File.join(File.dirname(__FILE__), 'infobot.yml'), 'w') do |out|
      YAML.dump(@facts, out)
    end
  end
  
  def init
    # @log.debug "entering init()"
    YAML::load(File.read(File.join(@bot_root, 'tmp', 'infobot.yml')))
  end
  
  def reload(msg)
    @facts = init()
    msg.speak("ok, reloaded #{@facts.size} facts")
  end
  
end
