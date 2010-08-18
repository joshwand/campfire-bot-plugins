require 'open-uri'
require 'hpricot'
require 'tempfile'

class Bruce < CampfireBot::Plugin
  on_command 'bruce', :fail
  
  def fail(msg)
    # Scrape random fail
    fail = (Hpricot(open('http://www.schneierfacts.com/'))/'p.fact').first
    msg.speak(fail.inner_html)
  rescue => e
    msg.speak e
  end
end