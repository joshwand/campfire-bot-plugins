require 'rubygems'
require 'yahoo-weather'

class Weather < CampfireBot::Plugin
  on_command 'weather', :weather
  on_command 'w',       :weather

  def weather(msg)
    met_cities = {
      'adelaide'  => '1099805',
      'brisbane'  => '1100661',
      'canberra'  => '1100968',
      'darwin'    => '1101597',
      'hobart'    => '1102670',
      'melbourne' => '1103816',
      'perth'     => '1098081',
      'sydney'    => '1105779'
    }
    imp_cities = {
      'denver'        => '2391279',
      'mill valley'   => '2451166'
    }

    city_id = met_cities[(msg[:message]).downcase]  # check metric cities, or...
    if city_id 
        deg_pref = 'c'
    else
        deg_pref = 'f'
        city_id = imp_cities[(msg[:message]).downcase]  # select imperial cities, or
        city_id ||= imp_cities['philadelphia'] if !city_id  # use default if no matches
    end
    data = YahooWeather::Client.new.lookup_by_woeid(city_id, deg_pref)
    msg.speak("#{data.title} - ")
    msg.speak("Now, #{data.condition.text}, " +
            "#{data.condition.temp} deg #{data.units.temperature} " +
            "(#{data.wind.chill} deg #{data.units.temperature} chill), " +
            "#{data.atmosphere.humidity}% RH, " +
            "#{data.wind.speed} #{data.units.speed} wind")
    msg.speak("#{data.forecasts.first.day}, #{data.forecasts.first.text}, " +
            "high #{data.forecasts.first.high}, " +
            "low #{data.forecasts.first.low} deg #{data.units.temperature}")
    msg.speak("#{data.forecasts.second.day}, #{data.forecasts.second.text}, " +
            "high #{data.forecasts.second.high}, " +
            "low #{data.forecasts.second.low} deg #{data.units.temperature}")
    msg.speak("( more info.: #{data.page_url} )")
  end
end
