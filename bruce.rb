require 'open-uri'
require 'hpricot'
require 'tempfile'

class Bruce < CampfireBot::Plugin
  on_command 'bruce', :fail
  
  def fail(msg)
    # Scrape random fail
    bruce = (Hpricot(open('http://www.schneierfacts.com/'))/'p.fact').first
    msg.speak(CGI.unescapeHTML(bruce.inner_html))
  rescue => e
    msg.speak e
  end
end