require 'open-uri'
require 'hpricot'

class Chuck < CampfireBot::Plugin
  on_command 'chuck', :chuck
  
  def initialize
    @log = Logging.logger["CampfireBot::Plugin::Chuck"]
  end
  
  def chuck(msg)
    url = "http://www.chucknorrisfacts.com/all-chuck-norris-facts?page=#{rand(172)+1}"
    doc = Hpricot(open(url))
    
    facts = []
    
    (doc/".item-list a.createYourOwn").each do |a_tag|
      facts << CGI.unescapeHTML(a_tag.inner_html)
    end
    
    msg.speak(facts[rand(facts.size)])
  end
end