require 'open-uri'
require 'hpricot'
require 'tempfile'

class Xkcd < CampfireBot::Plugin
  BASE_URL = 'http://xkcd.com/'
  
  on_command 'xkcd', :xkcd
  
  def xkcd(msg)    
    # Get the comic info
    comic = case msg[:message].split(/\s+/)[0]
    when 'latest'
      fetch_latest
    when 'random'
      fetch_random
    when /d+/
      fetch_comic(msg[:message].split(/\s+/)[0])
    else
      fetch_random
    end
    
    msg.speak comic['src']
    msg.speak comic['title']
  end
  
  private
  
  def fetch_latest
    fetch_comic
  end
  
  def fetch_random
    # Fetch the latest page and then find the link to the previous comic.
    # This will give us a number to work with (that of the penultimate strip).
    fetch_comic(rand((Hpricot(open(BASE_URL))/'//*[@accesskey="p"]').first['href'].gsub(/\D/, '').to_i + 1))
  end
  
  def fetch_comic(id = nil)
    # Rely on the comic being the last image on the page with a title attribute
    (Hpricot(open("#{BASE_URL}#{id.to_s + '/' if id}"))/'img[@title]').last
  end
end