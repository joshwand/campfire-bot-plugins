require 'open-uri'
require 'hpricot'
require 'tempfile'

class Garfield < CampfireBot::Plugin
  BASE_URL    = 'http://images.ucomics.com/comics/ga'
  START_DATE  = Date.parse('1978-06-19')
  END_DATE    = Date.today
  
  on_command 'garfield', :garfield
  
  def garfield(msg)    
    comic = case msg[:message].split(/\s+/)[0]
    when 'random'
      fetch_random
    when /d+/
      fetch_comic(msg[:message].split(/\s+/)[0])
    else
      fetch_random
    end
    
    msg.speak(comic)
  end
  
  private
  
  def fetch_random
    fetch_comic(rand(number_of_comics))
  end
  
  def fetch_comic(id = nil)
    date = id_to_date(id)
    "#{BASE_URL}/#{date.strftime('%Y')}/ga#{date.strftime('%y%m%d')}.gif"
  end
  
  def id_to_date(id)
    (START_DATE + id.days).to_date
  end
  
  def number_of_comics
    (END_DATE - START_DATE).to_i
  end
end