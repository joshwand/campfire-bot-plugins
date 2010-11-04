require 'yahoo-weather'

class Weather < CampfireBot::Plugin
  on_command 'weather', :weather
  
  def weather(msg)
    cities = {
      'adelaide'  => '1099805',
      'brisbane'  => '1100661',
      'canberra'  => '1100968',
      'darwin'    => '1101597',
      'hobart'    => '1102670',
      'melbourne' => '1103816',
      'perth'     => '1098081',
      'sydney'    => '1105779'
    }
    
    city_id = cities[(msg[:message]).downcase]  # select city, or
    city_id ||= cities['canberra']              # use default if no matches
    
    data = YahooWeather::Client.new.lookup_by_woeid(city_id, 'c')
    
    msg.speak("#{data.title} - #{data.condition.text}, #{data.condition.temp} deg C (high #{data.forecasts.first.high}, low #{data.forecasts.first.low})")
  end
end