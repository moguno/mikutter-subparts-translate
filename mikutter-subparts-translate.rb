require "net/http"
require "net/https"
require "json"
require "rexml/document"

Plugin.create(:"mikutter-subparts-translate") {
  miquire :mui, 'sub_parts_message_base'

  TOKEN = {
    :time_limit => Time.now - 1,
    :access_token => nil,
  }

  def get_access_token(client_id, client_secret)
    if Time.now < TOKEN[:time_limit]
      TOKEN[:access_token]
    else
      data = {
        "client_id" => client_id,
        "client_secret" => client_secret,
        "scope" => "http://api.microsofttranslator.com",
        "grant_type" => "client_credentials"
      }

      url = "https://datamarket.accesscontrol.windows.net/v2/OAuth2-13"

      res = Net::HTTP.post_form(URI.parse(url), data)

      if res.code == "200"
        json = JSON.parse(res.body)

        TOKEN[:access_token] = json["access_token"]
        TOKEN[:time_limit] = Time.now + json["expires_in"].to_i 

        TOKEN[:access_token]
      else
        nil
      end
    end
  end

  def translate(token, text)
    url = URI.parse("http://api.microsofttranslator.com/V2/Http.svc/Translate?to=ja&text=#{URI.escape(text)}")

    header = {
      "Authorization" => "Bearer #{token}"
    }

    res = Net::HTTP.start(url.host, url.port) { |http|
      http.get(url, header)
    }

    if res.code == "200"
      doc = REXML::Document.new(res.body)
      doc.get_elements("/string")[0].text
    else
      nil
    end
  end


  class Gdk::SubPartsTranslate < Gdk::SubPartsMessageBase
    register

    @translated_messages = nil

    def show_header?
      false
    end

    def show_icon?
      false
    end

    def messages
      @translated_messages = if helper.message[:translated_text]
        if !@translated_messages
          message = Message.new(:message => helper.message[:translated_text], :system => true)
          message.user[:idname] = "翻訳家に憧れるみくったーちゃん"
          Messages.new([message])
        else
          @translated_messages
        end
      else
        nil
      end

      @translated_messages
    end

    def text_max_line_count(message)
      8192
    end
  end

  settings(_("翻訳")) {
    input(_("クライアントID"), :translator_client_id)
    input(_("顧客の秘密"), :translator_client_secret)
  }


  command(:translate,
          :name => _("翻訳"),
          :condition => lambda { |opt| Plugin::Command[:HasMessage] },
          :visible => true,
          :role => :timeline) { |opt|

    Thread.new {
      token = get_access_token(UserConfig[:translator_client_id], UserConfig[:translator_client_secret])

      opt.messages[0][:translated_text] = translate(token, opt.messages[0].to_s)

      Delayer.new {
        widget = Plugin[:gtk].widgetof(opt.widget)
        widget.modified(opt.messages[0])
      }
    }
  }
}
