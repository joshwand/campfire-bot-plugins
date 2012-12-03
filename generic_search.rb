require 'nokogiri'
require 'cgi'
require 'net/http'
require 'pp'
require 'action_view'
require 'addressable/uri'

include ActionView::Helpers::TextHelper

#
# Search sites like Google and Wikipedia
#
# You configure the command name and URL pattern.  Given a search
# term, it attempts to respond with the URL of the first search
# result.  It does so by simply inserting the term into the URL at the
# '%s'.  If the url redirects, it responds with the redirect target
# instead, so you get a hint about what you'll see.  Otherwise, you
# get just the expanded url pattern.
#
# This is useful for a wide range of sites or services.  Sample config:
#
# generic_search_commands:
#   wikipedia: "http://en.wikipedia.org/wiki/Special:Search?search=%s&go=Go"
#   google:
#   	url: "http://www.google.com/search?hl=en&q=%s&btnI=I'm+Feeling+Lucky&aq=f&oq="
#     result_xpath: //h3/a
#   jira:
#     url: "https://user:p4ssw0rd@jira.domain.com/jira/sr/jira.issueviews:searchrequest-printable/temp/SearchRequest.html?jqlQuery=summary+~+%s+OR+description+~+%s+OR+comment+~+%s&tempMax=12"
#     result_xpath: //td[@class='nav summary']/a
#     more_results_subs:
#       pattern: tempMax=12
#       replacement: tempMax=250
#   data:
#     url: "http://api.domain.com:1234/Location?param=%s"
#     result_xpath: feed/entry/link[@rel='self']
#     max_results: 1
#     result_href_append: ?schema=5
#     result_filter: .*/(\d+)
#   php: "http://us3.php.net/manual-lookup.php?pattern=%s&lang=en"
#   letmegooglethatforyou: "http://letmegooglethatforyou.com/?q=%s"
#
# Note that the last site never redirects, which is fine.
#
# max_results (optional) to return for requests.  Will be set to the
#   plugin's default value if omitted.
#
# result_href_append (optional) is added to the end of result link
#   references (URL)
#
# result_filter (optional) is applied to result contents to extract
#   only pertinent information.
#
# more_results_subs (optional) changes the URL linking to the full
#   search results to make a query that's more useful for the user.
#
#   When results do not have any content besides an link references
#   (href URL), the content produced will be that link passed through
#   result_filter.  That optional parameter is highly recommended in
#   those occasions.
class GenericSearch < CampfireBot::Plugin
  attr_reader :commands

  DEFAULT_RESULTS = 6
  MAX_RESULTS = 12
  CONTENT_MAX_LENGTH = 60

  def initialize
    @log = Logging.logger["CampfireBot::Plugin::GenericSearch"]
    @commands = bot.config["generic_search_commands"] || {}
    commands.each { |c, h|
      method = "do_#{c}_command".to_sym
      self.class.send(:define_method, method) {|msg|

        if h.is_a?(Hash)
          @log.debug "url: #{h['url']}, term: #{CGI.escape(msg[:message])}"
          initial_url = h['url'].gsub(/%s/, CGI.escape(msg[:message]))
          redir_url, response = http_peek(initial_url)
          @log.debug "peeked #{response}, url: #{redir_url}"
          results = ml_scrape(response.read_body, redir_url,
              h['result_xpath'], h['default_results'] || DEFAULT_RESULTS,
              h['result_href_append'], h['result_filter'])
          @log.debug "done, got #{results.count()} results from " +
              "the #{h['result_xpath']} tag of #{response}"

          msg.speak(h['preface']) unless h['preface'].nil?
          results.each { |r|
            msg.speak(r)
          }
          redir_uri = Addressable::URI.parse redir_url
          obfus_uri = redir_uri.omit(:user, :password)

          if h['more_results_subs']
            @log.debug "obfus #{obfus_uri.class}, .to_s #{obfus_uri.to_s}"
            @log.debug "pattern #{h['more_results_subs']['pattern']}, " +
                "substitition #{h['more_results_subs']['replacement']}"
            obfus_uri.to_s.gsub!(Regexp.new( \
                h['more_results_subs']['pattern'] ),
                h['more_results_subs']['replacement'] )
          end

          msg.speak("( search results: #{obfus_uri} )")

        else
          url = sprintf(h, CGI.escape(msg[:message]))
          redir_url, response = http_peek(url)
          @log.debug "done, saying: #{response}, url: #{url}"
          msg.speak(redir_url)
        end
      }
      self.class.on_command(c, method)
      @log.debug "set up on_command... #{method}, #{h}"
    }
  end

  protected

  # Follow the url to see if it redirects.  If so, return the URL of the
  # redirect and response data.  Otherwise, return the original URL and
  # data instead.

  def http_peek(url)
    @log.debug "http_peek... #{url}"
    uri = Addressable::URI.parse url
    if uri.port
      http = Net::HTTP.new(uri.host, uri.port)
    else
      http = Net::HTTP.new(uri.host,
          Addressable::URI.port_mapping[uri.scheme])
    end
    http.open_timeout = 5

    # Unfortunately the net/http(s) API can't seem to do this for us,
    # even if we require net/https from the beginning (ruby 1.8)
    if uri.scheme == "https"
      require 'net/https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    if bot.config["log_level"] == "debug"
      http.set_debug_output $stderr
    end

    begin
      res = http.start { |http|
        @log.debug "http.start, http object: " + 
            PP.singleline_pp(http, '')
        req = Net::HTTP::Get.new(uri.request_uri,
            { 'User-Agent' => 'campfire-bot/20110709 ' +
                '(x86_64-unknown-linux-gnu) ruby-stdlib-net/1.8.7' })

        if uri.user != nil && uri.user != "" &&
            uri.password != nil && uri.password != ""
          req.basic_auth uri.user, uri.password
        end

        response = http.request req
        @log.debug "http.start, response: " + 
            PP.singleline_pp(response, '')
        response
      }

    rescue Exception => e
      @log.error "Exception... #{e.class.name}, #{e.message}"
    end

    case res
    when Net::HTTPRedirection
      uri.merge({ :host => res.header['Location'] })
      @log.debug "following HTTPRedirection... res: #{res}, uri: " +
          "#{uri.omit(:user, :password)}, header: #{res.header['Location']}"
      [res.header['Location'], res]

    else # Net::HTTPSuccess or error
      @log.debug "proper location... res: #{res}, uri: #{uri.omit(:user, :password)}"
      [url, res]
    end
  end

  # Parse the passed-in 'body_ml' markup string that has (presumably)
  # come from 'url' and provide back the contents of specific nodes of
  # the html/xml per each of 'result_xpaths'.  The centent text will be
  # filtered by way of 'result_filter', and 'res_href_append' will be
  # added to the end of resulting link URLs.
  def ml_scrape(body_ml, url, result_xpaths, max_results = nil, 
      res_href_append = nil, result_filter = nil)

    result_xpaths = [ result_xpaths ] unless result_xpaths.class == Array
    max_results = MAX_RESULTS if max_results > MAX_RESULTS

    @log.debug "ml_scraping for #{max_results} results with " +
        "'#{result_xpaths.join(', ')}' in #{body_ml.length} bytes " +
        "from #{url}"

    ret=[]
    doc = Nokogiri.parse(body_ml)
    result_xpaths.each do |result_xpath|
      @log.debug "result_xpath: #{result_xpath}"
      doc.search(result_xpath)[0..max_results-1].each do |link|
        @log.debug "link: " + PP.singleline_pp(link, '')

        # ...in case no 'href' attr. for tag
        result_href = link.content if result_filter

        if link['href'] && link['href'].start_with?("/")
          uri = Addressable::URI.parse url
          result_href = uri.omit(:user, :password) + link['href']

        elsif link['href']
          result_href = link['href']
        end


        if link.content == nil || link.content == ""
          content = result_href
        else
          content = link.content
        end

        @log.debug "content: " + PP.singleline_pp(content, '')
        if content && result_filter
          content = CGI.unescape(content.gsub(Regexp.new(result_filter), 
              '\1'))
        end

        @log.debug "content: #{content}, href+: " +
            "#{result_href}#{res_href_append}"
        ret.push("#{truncate(content, 
            :length => CONTENT_MAX_LENGTH, :separator => ' ')} " +
            "#{result_href}#{res_href_append}")
      end
    end

    ret
  end
end
