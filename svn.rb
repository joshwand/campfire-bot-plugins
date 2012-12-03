require 'open-uri'
require 'hpricot'
require 'tempfile'
require 'rexml/document'
require 'addressable/uri'

class Svn < CampfireBot::Plugin

  #at_interval 20.minutes, :check_svn
  #on_command 'checksvn', :checksvn_command
  on_command 'svn', :lookup_commit_details


  def initialize
    # log "initializing... "
    @bot_root = bot.config['bot_root'].nil? ? "/opt/campfire-bot" : \
        bot.config['bot_root']
    @data_file  = File.join(@bot_root, 'tmp',
        "svn-#{bot.environment_name}-#{bot.config['room']}.yml")
    @cached_revisions = YAML::load(File.read(@data_file)) rescue {}
    @last_checked ||= 10.minutes.ago
    @urls = bot.config['svn_urls']
    @log = Logging.logger["CampfireBot::Plugin::Svn"]
  end

  # respond to checkjira command-- same as interval except we answer with 'no issues found' if 
  def checksvn_command(msg)
    msg.speak "no new commits since I last checked #{@lastlast} ago" if !check_svn(msg)
  end

  # respond with details about a particular commit
  def lookup_commit_details(msg)
    rev = msg[:message]
    commit = fetch_svn_commit(rev).first
    messagetext = "#{commit[:author]} committed revision #{commit[:revision]} " +
        "#{time_ago_in_words(commit[:date])} ago:\n"

    messagetext += "\n#{commit[:message]}\n"
    messagetext += "----\n"
    commit[:paths].each do |path|
        messagetext += path[:action] + " " + path[:path] + "\n"
    end

    msg.paste(messagetext)

    messagetext = "More detail can be found at " + bot.config['svn_webui_url']
    msg.speak(messagetext)

    @log.info messagetext
  end
  
  
  def check_svn(msg)
    
    saw_a_commit = false
    old_cache = Marshal::load(Marshal.dump(@cached_revisions)) # since ruby doesn't have deep copy
    
    @lastlast = time_ago_in_words(@last_checked)
    commits = fetch_svn_urls
    
    commits.each do |commit|
      # p commit
      if new?(commit, old_cache)
        saw_an_issue = true

        @cached_revisions = update_cache(commit, @cached_revisions) 
        flush_cache(@cached_revisions)
    
        messagetext = "#{commit[:author]} committed revision #{commit[:revision]} " +
          "#{time_ago_in_words(commit[:date])} ago on #{commit[:url]}:\n"

        messagetext += "\n#{commit[:message]}\n"
        messagetext += "----\n"
        commit[:paths].each do |path|
          messagetext += path[:action] + " " + path[:path] + "\n"
        end
        
        msg.paste(messagetext)
        @log.info messagetext
          
      end
    end

    @last_checked = Time.now
    @log.info "no new commits." if !saw_a_commit
  
    saw_a_commit
  end
  
  protected

  # fetch jira url and return a single commit Hash
  def fetch_svn_commit(rev)
    url_str = bot.config['svn_root_url']
    commit = []
    begin
      @log.info "checking #{url_str} for new commit..."

      # https://username:password@svn.host.com:8080/svn/path/in/repo/
      url = Addressable::URI.parse(url_str)

      @log.debug PP.singleline_pp(url.to_hash, '')
      xmldata = `svn log --xml -v -r #{rev} #{url.omit(:user, :password)}`
      doc = REXML::Document.new(xmldata)
    
      doc.elements.inject('log/logentry', commit) do |commit, element|
        commit.push({:url => url}.merge(parse_entry_info(element)))
      end
      @log.debug PP.singleline_pp(commit, '')

    rescue Exception => e
      @log.error "error connecting to svn: #{e.message}"
    end
    return commit
  end

  # fetch jira url and return a list of commit Hashes
  def fetch_svn_urls()
    urls = bot.config['svn_urls']
    commits = []
    urls.each do |url_str|
      begin
        @log.info "checking #{url_str} for new commits..."

        # https://username:password@svn.host.com:8080/svn/path/in/repo/
        url = Addressable::URI.parse(url_str)

        xmldata = `svn log --username #{url.user} --password #{url.password} --xml -v --limit 15 #{url.omit(:user, :password)}`
        doc = REXML::Document.new(xmldata)
      
        doc.elements.inject('log/logentry', commits) do |commits, element|
          commits.push({:url => url}.merge(parse_entry_info(element)))
        end

      rescue Exception => e
        @log.error "error connecting to svn: #{e.message}"
      end
    end
    return commits
  end

  # extract commit hash from individual revision xml element
  def parse_entry_info(xml_element)
    
    revision =   xml_element.attributes['revision']
    author =     xml_element.elements['author'].text
    date =       DateTime.parse(xml_element.elements['date'].text)
    message =    xml_element.elements['msg'].text
    
    paths = xml_element.elements.collect('paths/path') do |e|
      {
      :action => e.attributes['action'],
      :path => e.text
      }
    end
    
    return {
      :revision => revision,
      :author => author,
      :message => message,
      :date => date,
      :paths => paths
    }
  end
  
  # has this commit been seen before this run?
  def new?(commit, old_cache)
    !old_cache.key?(commit[:url]) or old_cache[commit[:url]] < commit[:revision].to_i
  end
  
  # only update the cached highest revision if it is in fact the highest revision
  def update_cache(commit, cache)
    cache[commit[:url]] = commit[:revision].to_i if new?(commit, cache)
    cache
  end

  # write the cache to disk
  def flush_cache(cache)
    File.open(@data_file, 'w') do |out|
      YAML.dump(cache, out)
    end
  end
  
  
  
  # 
  # time/utility functions
  # 
  
  
  def time_ago_in_words(from_time, include_seconds = false)
    distance_of_time_in_words(from_time, Time.now, include_seconds)
  end
  
  def distance_of_time_in_words(from_time, to_time = 0, include_seconds = false)
    from_time = from_time.to_time if from_time.respond_to?(:to_time)
    to_time = to_time.to_time if to_time.respond_to?(:to_time)
    distance_in_minutes = (((to_time - from_time).abs)/60).round
    distance_in_seconds = ((to_time - from_time).abs).round

    case distance_in_minutes
      when 0..1
        return (distance_in_minutes == 0) ? 'less than a minute' : '1 minute' unless include_seconds
        case distance_in_seconds
          when 0..4   then 'less than 5 seconds'
          when 5..9   then 'less than 10 seconds'
          when 10..19 then 'less than 20 seconds'
          when 20..39 then 'half a minute'
          when 40..59 then 'less than a minute'
          else             '1 minute'
        end

        when 2..44           then "#{distance_in_minutes} minutes"
        when 45..89          then 'about 1 hour'
        when 90..1439        then "about #{(distance_in_minutes.to_f / 60.0).round} hours"
        when 1440..2879      then '1 day'
        when 2880..43199     then "#{(distance_in_minutes / 1440).round} days"
        when 43200..86399    then 'about 1 month'
        when 86400..525599   then "#{(distance_in_minutes / 43200).round} months"
        when 525600..1051199 then 'about 1 year'
        else                      "over #{(distance_in_minutes / 525600).round} years"
    end
  end
  
end
