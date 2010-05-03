require 'open-uri'
require 'hpricot'
require 'tempfile'

class LolCats < CampfireBot::Plugin
  on_command 'lolcat', :lolcats
  
  def initialize
    @log = Logging.logger["CampfireBot::Plugin::Lolcat"]
  end
  
  def lolcats(msg)
    # Scrape random lolcat
    lolcat = (Hpricot(open('http://icanhascheezburger.com/?random#top'))/'div.snap_preview img').first['src']
    msg.speak(lolcat)
  end
end