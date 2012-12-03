require 'yaml'
require 'tzinfo'

class Infobot < CampfireBot::Plugin
  
  Infobot::QUESTION_PHRASES = ["what's", "what is", "what are",
      "who is", "who's", "who are", "where is", "where's", "where are",
      "how's", "how is", "how are"]

  Infobot::DEFINE_REGEXP = /(no, )*(.+)[ '](s|is|are) ([^\?]+)(?!\?)$/
  Infobot::RESPOND_REGEXP =
      /(#{QUESTION_PHRASES.join("|")}) ([^\?]+)(?=\?)*/

    on_message Regexp.new("^#{bot.config['nickname']},\\s+#{RESPOND_REGEXP.source}",
        Regexp::IGNORECASE),        :respond
    on_message Regexp.new("^#{bot.config['nickname']},\\s+#{DEFINE_REGEXP.source}",
        Regexp::IGNORECASE),        :define

    on_command 'fact_help',         :usage
    on_command 'help_facts',        :usage

    on_command 'reload_facts',      :reload

    on_command 'what_do_you_know',  :list_facts
    on_command 'what_do_you_know?', :list_facts
    on_command 'whatdoyouknow',     :list_facts
    on_command 'whatdoyouknow?',    :list_facts

    on_command 'forget',            :forget_fact
    on_command 'forget_about',      :forget_fact

  def initialize
    @log = Logging.logger["CampfireBot::Plugin::Infobot"]
    @bot_root = bot.config['bot_root'].nil? ? "/opt/campfire-bot" : \
        bot.config['bot_root']
    # @log.debug "entering initialize()"
    
  end

  def respond(msg)
    # @log.debug "entering respond()"
    @facts ||= init() || Hash.new
    @log.debug msg[:message]
    @log.debug msg[:message] =~ RESPOND_REGEXP # Regexp.new("^#{Bot.instance.config['nickname']},\\s+#{RESPOND_REGEXP.source}", Regexp::IGNORECASE)
    @log.debug "1, 2, 3: #{$1}, #{$2}, #{$3}"
    @log.info "Checking for fact: got #{@facts.keys.count} of them"
    if !@facts.has_key?($2.downcase)
      msg.speak("Sorry, I don't know what #{$2} is.")
    else
      fact = @facts[$2.downcase]

      moods = [ "cheerful", "cheerful", "snarky", "snarky", "snarky", 
          "moody", "proper", "proper" ]

      response = case moods.choice
        when "cheerful" then
          # "Somebody named John Smith told me the sky is blue 29
          # minutes ago... Or maybe it was the other way around?!?"
          "Somebody named #{fact[:authority]} told me " +
          "#{fact[:fact_name]} " + 
          ( $2[-1].chr == "s" ? "are " : "is " ) + 
          "#{fact[:detail]} #{time_ago_in_words(fact[:date])} " +
          "ago... Or maybe it was the other way around?!?"

        when "snarky"   then
          # "Well, the sky is blue. At least that's what John Smith
          # thinks. He told me so on Thursday, 12/22 around 3:30 PM or
          # so.  You gonna trust HIM?!?
          "Well, #{fact[:fact_name]} " + 
              ( $2[-1].chr == "s" ? "are " : "is " ) + 
              "#{fact[:detail]}. At least that's what " +
              "#{fact[:authority]} thinks. ...told me so on " +
              "#{fact[:date].strftime("%A %m/%d")}, around " +
              "#{round_time(fact[:date]).strftime("%l:%M %p")} or " +
              "so. " +
              [ "You gonna trust it?!?", "What do you think of that?", 
                  "Seems a little fishy to me...", "I wouldn't put " +
                  "too much stock in it though.", "...didn't seem " +
                  "too sure about it though.", "... or maybe they " +
                  "DIDN'T...", "" ].choice

        when "moody"    then
          # "blue."
          # "blue... blue, already.  JEESH!,
          [ "#{fact[:detail]}.",
              "#{fact[:detail]}... #{fact[:detail]}... " +
              "#{fact[:detail]}, already.  JEESH!", "I'm busy.",
              "Look, can we talk about this in a bit?",
              "Really busy. Production issue...",
              "How am *I* supposed to know THAT!?!",
              "Sorry, that's #21... Maybe try tomorrow?",
              "What's the magic word? (after the ?, okay)",
              "#{fact[:detail]}. Maybe you can ask NICER next " +
              "time... Hmmmph", "How much money do you have?" ].choice 

        else # proper
          # "Mike, the sky is blue, according to John Smith, as of Thu
          # 12/22 08:32 PM (29 minutes) ago."
          "#{msg[:person].split(" ")[0]}, #{fact[:fact_name]} " + 
              ( $2[-1].chr == "s" ? "are " : "is " ) + 
              "#{fact[:detail]}, according to #{fact[:authority]}, " +
              "as of #{fact[:date].strftime("%a %m/%d, %l:%M %p")} " +
              "ET (#{time_ago_in_words(fact[:date])} ago)."
      end

      msg.speak(response)
    end
  end

  def define(msg)
    @log.debug 'entering define()'
    @facts ||= init() || Hash.new()
    @log.debug PP.singleline_pp(@facts, '')
    @log.debug msg[:message]
    @log.debug msg[:message] =~ Regexp.new("^#{bot.config['nickname']},\\s+#{DEFINE_REGEXP.source}",
        Regexp::IGNORECASE)
    @log.debug "1, 2, 3, 4: #{$1}, #{$2}, #{$3}, #{$4}"
    if ! QUESTION_PHRASES.include?("#{$2.downcase} #{$3.downcase}")

      @facts[$2.downcase] ||= Hash.new()
      @facts[$2.downcase][:fact_name] = $2
      @facts[$2.downcase][:detail] = $4 
      @facts[$2.downcase][:authority] = msg[:person]
      tz = TZInfo::Timezone.get('America/New_York')
      @facts[$2.downcase][:date] = tz.utc_to_local(Time.now)

      @log.debug "Done setting a fact: got #{@facts.keys.count} of them"
      result = "Okay, #{$2} is now #{$4}"
      result = "Okay, #{$2} are now #{$4}" if $2[-1].chr == "s"
      msg.speak(result)
      File.open(File.join(@bot_root, 'tmp', 'infobot.yml'), 'w') do |out|
        out.flock(File::LOCK_EX)
        YAML.dump(@facts, out)
        @log.debug "Stored #{@facts.keys.count} facts to #{out}"
        out.flock(File::LOCK_UN)
      end
    else
      @log.debug "Trapped definition of a question word, re-process " +
          "as question"
      msg.speak("Not going to define the word '#{$2}', assuming " +
          "that's actually a question... (use a '?')")
      msg[:message] << "?"
      respond(msg)
    end

  end
  
  def init
    # @log.debug "entering init()"
    YAML::load(File.read(File.join(@bot_root, 'tmp', 'infobot.yml')))
  end
  
  def reload(msg)
    @facts ||= init() || Hash.new
    msg.speak("ok, reloaded #{@facts.size} facts")
  end
  
  def list_facts(msg)
    @facts ||= init() || Hash.new
    if @facts.size > 0
      msg.speak("Here are the things I know about: " +
          "#{@facts.keys.join(", ")}")
    else
      msg.speak("I don't know about anything at the moment")
    end
  end

  def forget_fact(msg)
    @facts ||= init() || Hash.new
    if @facts.delete(msg[:message])
      @log.info "forgot #{msg[:message]}"
      File.open(File.join(@bot_root, 'tmp', 'infobot.yml'), 'w') do |out|
        out.flock(File::LOCK_EX)
        YAML.dump(@facts, out)
        @log.debug "Stored #{@facts.keys.count} facts to #{out}"
        out.flock(File::LOCK_UN)
      end
      msg.speak("#{msg[:message]}? Never heard of it...")
    else
      @log.info "never knew #{msg[:message]} in the first place"
      msg.speak("#{msg[:message]}? Never heard of it in the first " +
          "place, anyways...")
    end
  end

  # Bot is to provide advice on how to invoke this plugin's various
  # functionality.
  def usage(m)
    m.speak("Tell the bot facts like " +
        "'#{bot.config['nickname']}, the <noun> is <adjective>'")

    m.speak("Ask it later like " +
        "'#{bot.config['nickname']}, what is the <noun>? (case is " +
        "not sensitive)")

    m.speak("Ex. '#{bot.config['nickname']}, the sky is blue' and " +
        "'#{bot.config['nickname']}, what is the sky?'")

    m.speak("Other commands include '#{bot.config['nickname']}, " +
        "what_do_you_know' and '#{bot.config['nickname']}, " +
        "forget_about <noun>'")

    m.speak("If you have trouble please try again, basing your query " +
        "off of an example above. Otherwise, please open a " +
        "'Account Request Campfire/New Relic/Splunk' ticket at " +
        "https://www.teamccp.com/jira, and assign it to 'Andrew " +
        "Burnheimer'.")

  end

  def time_ago_in_words(from_time, include_seconds = false)
    tz = TZInfo::Timezone.get('America/New_York')
    @log.debug "Time.now: #{Time.now}, Time zone name: " +
        "#{Time.now.strftime("%H:%M %Z")}, "
    distance_of_time_in_words(tz.local_to_utc(from_time), Time.now, 
        include_seconds)
  end

  def distance_of_time_in_words(from_time, to_time = 0,
      include_seconds = false)
    from_time = from_time.to_time if from_time.respond_to?(:to_time)
    to_time = to_time.to_time if to_time.respond_to?(:to_time)
    distance_in_minutes = (((to_time - from_time).abs)/60).round
    distance_in_seconds = ((to_time - from_time).abs).round

    case distance_in_minutes
      when 0..1
        return (distance_in_minutes == 0) ? \
            'less than a minute' : '1 minute' unless include_seconds
        case distance_in_seconds # include_seconds == true
          when 0..4   then 'less than 5 seconds'
          when 5..9   then 'less than 10 seconds'
          when 10..19 then 'less than 20 seconds'
          when 20..39 then 'half a minute'
          when 40..59 then 'less than a minute'
          else             '1 minute'
        end

        when 2..44           then "#{distance_in_minutes} minutes"

        when 45..89          then 'about 1 hour'
        when 90..1439        then "about #{(distance_in_minutes.to_f / 
                                   60.0).round} hours"

        when 1440..2879      then '1 day'
        when 2880..43199     then "#{(distance_in_minutes / 
                                   1440).round} days"

        when 43200..86399    then 'about 1 month'
        when 86400..525599   then "#{(distance_in_minutes / 
                                   43200).round} months"

        when 525600..1051199 then 'about 1 year'
        else                      "over #{(distance_in_minutes / 
                                   525600).round} years"
    end
  end

  # Pass in a time, and get one back rounded to the nearest
  # approximation position in minutes (0, 15, 30, etc.)
  def round_time(time, major = 15)
    time + 60 * -( time.min - ( ( time.min.to_f / major ).round * major ) )
  end

end
