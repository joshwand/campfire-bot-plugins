require 'open-uri'
require 'hpricot'
require 'tempfile'

class Calvin < CampfireBot::Plugin
  BASE_URL    = 'http://marcel-oehler.marcellosendos.ch/comics/ch/'
  START_DATE  = Date.parse('1985-11-18')
  END_DATE    = Date.parse('1995-12-31') # A sad day
  
  on_command 'calvin', :calvin
  
  def calvin(msg)    
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
    "#{BASE_URL}#{date.strftime('%Y')}/#{date.strftime('%m')}/#{date.strftime('%Y%m%d')}.gif"
  end
  
  def id_to_date(id)
    (START_DATE + id.days).to_date
  end
  
  def number_of_comics
    (END_DATE - START_DATE).to_i
  end
end