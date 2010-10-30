require 'open-uri'
require 'hpricot'
require 'tempfile'

class Fail < CampfireBot::Plugin
  on_command 'fail', :fail
  
  def fail(msg)
    # Scrape random fail
    fail = (Hpricot(open('http://failblog.org/?random#top'))/'div.entry img').first

    msg.speak(fail['src'])
  rescue => e
    msg.speak e
  end
end