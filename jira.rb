require 'open-uri'
require 'hpricot'
require 'tempfile'
require 'rexml/document'
require 'addressable/uri'
require 'tzinfo'

#
# JIRA plugin
# 
# Checks JIRA for new issues periodically and posts them to the room
# 
# In your config.yml you can either specify a single URL or a list of URLs, e.g.
# 
#   jira_poll_url: http://your_jira_url
#   # OR
#   jira_poll_url: 
#     - http://your_jira_url
#     - http://your_jira_url2
#
# Also supports looking up and reporting back a few details on a
# particular ticket
#
# A single URL should be configured in config.yml for lookups, e.g.
# 
#   jira_lookup_url: http://your_jira_url
# 


class Jira < CampfireBot::Plugin
  
  MAX_RESPONSES = 6

  at_interval 3.minutes, :check_jira
  on_command 'checkjira', :checkjira_command
  on_command 'jira', :lookup_ticket
  on_command 'j',    :lookup_ticket
  
  def initialize
    # log "initializing... "
    @bot_root = bot.config['bot_root'].nil? ? "/opt/campfire-bot" : \
        bot.config['bot_root']
    @data_file  = File.join(@bot_root, 'tmp', "jira-#{bot.environment_name}.yml")
    @cached_ids =  YAML::load(File.read(@data_file)) rescue {}
    @last_checked = @cached_ids[:last_checked] || 10.minutes.ago
    @log = Logging.logger["CampfireBot::Plugin::Jira"]
  end

  # respond to checkjira command-- same as interval except we answer
  # with 'no issues found' if there are no issues
  def checkjira_command(msg)
    begin
      msg.speak "no new issues since I last checked #{@lastlast} ago" \
          if !check_jira(msg)
    rescue 
      msg.speak "sorry, we had trouble connecting to JIRA."
    end
  end

  def lookup_ticket(msg)
    tickets = msg[:message]

    msg.speak("Will only lookup #{MAX_RESPONSES} issues or less at " +
        "a time")  if tickets.split(' ').size >= MAX_RESPONSES

    tickets.split(' ')[0..MAX_RESPONSES-1].each do |ticket|
      begin
        @log.info "looking up #{ticket} for #{msg[:person]}"
        lookupurl_str = bot.config['jira_lookup_url'].gsub(/%s/, CGI.escape(ticket))
        # lookupurl: "https://username:password@www.host.com/jira/si/jira.issueviews:issue-xml/%s/%s.xml"
        lookupurl = Addressable::URI.parse(lookupurl_str)
        @log.debug PP.singleline_pp(lookupurl.to_hash, '')
        xmldata = open(lookupurl.omit(:user, :password), 
          :http_basic_authentication=>[lookupurl.user, 
          lookupurl.password]).read
        doc = REXML::Document.new(xmldata)
        raise Exception.new("response had no content") if doc.nil?

        tik = {}

        doc.elements.inject('rss/channel/item', tik) do |tik, element|
          tik = parse_ticket_info(element)
          #comments = parse_ticket_for_comments(element)
        end

        @log.info "Examining #{tik[:title]}"

        update_tm_t = time_from_jira_time_string(tik[:updated])

        messagetext = "#{tik[:title]} - #{tik[:link]} - Type: " +
            "#{tik[:type]} - reported by #{tik[:reporter]}, " +
            "assigned to #{tik[:assignee]} - #{tik[:status]} " +
            "#{tik[:priority]}, updated " +
            "#{time_ago_in_words(update_tm_t)} ago"
        msg.speak(messagetext)
        @log.debug messagetext

      rescue Exception => e
        @log.error "error connecting to jira: #{e.message}, " +
            "#{e.backtrace}"
        msg.speak "Sorry, I had trouble finding info on #{ticket}."
        # @log.error "#{e.backtrace}"
      end
    end
  end
    
  def check_jira(msg)
    
    saw_an_issue = false
    old_cache = Marshal::load(Marshal.dump(@cached_ids))
        # since ruby doesn't have deep copy
    
    
    @lastlast = time_ago_in_words(@last_checked)
    @last_checked = Time.now
    

    tix = fetch_jira_poll_url
    raise if tix.nil?
      
    tix.each do |ticket|
      @log.info "Examining #{ticket[:title]}"
      if seen?(ticket, old_cache)
        saw_an_issue = true

        @cached_ids = update_cache(ticket, @cached_ids) 
        
        messagetext = "Unseen ticket: #{ticket[:type]} - " +
          "#{ticket[:title]} - #{ticket[:link]} - reported by " +
          "#{ticket[:reporter]}, assigned to #{ticket[:assignee]} - " +
          "#{ticket[:priority]}"

        msg.speak(messagetext)
        msg.play("vuvuzela") if ticket[:priority] == "Blocker"
        @log.info messagetext
          
      end
    end

    flush_cache(@cached_ids)
    @log.info "no new issues." if !saw_an_issue
  
    saw_an_issue
  end

  protected

  # fetch jira url and return a list of ticket Hashes
  def fetch_jira_poll_url()

    jiraconfig = bot.config['jira_poll_url']

    if jiraconfig.is_a?(Array)
      searchurls_str = jiraconfig 
    else 
      searchurls_str = [jiraconfig]
    end

    tix = []

    searchurls_str.each do |searchurl_str|
      begin
        @log.info "checking jira for new issues... #{searchurl_str}"
	# jira_poll_url: "http://username:password@www.host.com/jira/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?jqlQuery=project+%3D+OPS+ORDER+BY+updated+DESC%2C+priority+DESC%2C+created+ASC&tempMax=25&field=key&field=link&field=title&field=reporter&field=assignee&field=type&field=priority&field=updated"
        searchurl = Addressable::URI.parse(searchurl_str)
        @log.debug pp lookupurl.to_hash
        xmldata = open(searchurl.omit(:user, :password), \
          :http_basic_authentication=>[searchurl.user, searchurl.password]).read
        doc = REXML::Document.new(xmldata)
        raise Exception.new("response had no content") if doc.nil?
        doc.elements.inject('rss/channel/item', tix) do |tix, element|
          tix.push(parse_ticket_info(element))
        end
      rescue Exception => e
        @log.error "error connecting to jira: #{e.message}"
        # @log.error "#{e.backtrace}"
      end
    end
    return tix
  end

  # extract array of comments from an xml element (ticket)
  def parse_ticket_for_comments(xml)
    comments = []

    doc = REXML::Document.new(xml)

    doc.elements.inject('item/comments', comments) do |comments, element|
      comments.push(parse_comment_info(element))
    end

    return comments
  end

  # extract comment hash from individual xml element
  def parse_comment_info(xml_element)
    text = xml_element.elements['comment'].text rescue ""
    author = xml_element.elements['comment'].key['author'] rescue ""
    created = xml_element.elements['comment'].key['created'] rescue ""

    return {
      :text => text,
      :author => author,
      :created => created
    }
  end

  # extract ticket hash from individual xml element
  def parse_ticket_info(xml_element)
    id = xml_element.elements['key'].text rescue ""
    id, spacekey = split_spacekey_and_id(id) rescue ""

    link = xml_element.elements['link'].text rescue ""
    title = xml_element.elements['title'].text rescue ""
    reporter = xml_element.elements['reporter'].text rescue ""
    assignee = xml_element.elements['assignee'].text rescue ""
    type = xml_element.elements['type'].text rescue ""
    priority = xml_element.elements['priority'].text rescue ""
    updated = xml_element.elements['updated'].text rescue ""
    status = xml_element.elements['status'].text rescue ""

    return {
      :spacekey => spacekey,
      :id => id,
      :link => link,
      :title => title,
      :reporter => reporter,
      :assignee => assignee,
      :type => type,
      :priority => priority,
      :updated => updated,
      :status => status
    }
  end

  # extract the spacekey and id from the ticket id
  def split_spacekey_and_id(key)
    spacekey = key.scan(/^([A-Z]+)/).to_s
    id = key.scan(/([0-9]+)$/)[0].to_s.to_i
    return id, spacekey
  end

  # has this ticket been seen before this run?
  def seen?(ticket, old_cache)
    !old_cache.key?(ticket[:spacekey]) or 
        old_cache[ticket[:spacekey]] < ticket[:id]
  end

  # only update the cached highest ID if it is in fact the highest ID
  def update_cache(ticket, cache)
    cache[ticket[:spacekey]] = ticket[:id] if seen?(ticket, cache)
    cache
  end

  # write the cache to disk
  def flush_cache(cache)
    cache[:last_checked] = @last_checked
    File.open(@data_file, 'w') do |out|
      YAML.dump(cache, out)
    end
  end
  
  
  # 
  # time/utility functions
  # 

  def time_from_jira_time_string(jira_time_str)
    # Tue, 4 Oct 2011 13:21:37 -0400
    tm_h = {}
    tm_h[:day], tm_h[:date], tm_h[:mon], tm_h[:year], tm_h[:time],
        tm_h[:tz] = jira_time_str.split(' ')
    
    tm_h[:day] = tm_h[:day].chomp(',')
    tm_h[:h], tm_h[:m], tm_h[:s] = tm_h[:time].split(':')
    
    return Time.mktime(tm_h[:s], tm_h[:m], tm_h[:h], tm_h[:date],
        tm_h[:mon], tm_h[:year], tm_h[:day], tm_h[:yday], false, 
        tm_h[:tz])
  end

  def time_ago_in_words(from_time, include_seconds = false)
    tz = TZInfo::Timezone.get('America/New_York')
    @log.debug "Time.now: #{Time.now}, Time zone name: " +
        "#{Time.now.strftime("%H:%M %Z")}, "
    distance_of_time_in_words(from_time, tz.utc_to_local(Time.now), 
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
  
end
