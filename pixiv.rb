#! ruby -Ku
require 'net/http'
require 'uri'
require 'yaml'
require 'kconv'
require 'time'

class AccessPixiv
  #InitializeでCookieを取得しHeaderも構築する
  #成功:Trueを返す
  #失敗:Falseを返す
  def initialize(pixiv_id, pixiv_pass, user_agent, referer)
    get_cookie(pixiv_id, pixiv_pass, user_agent, referer)
  end

  #uriで指定されたページ内容を取得する
  #成功:対象URIの内容を返す
  #失敗:Falseを返す
  def get_file(uri, returnAsObj = false)
    sleep 1
    puts "  コンテンツを取得中 #{uri}"
    site = URI.parse(uri)
    begin
      Net::HTTP.start(site.host, 80) do |http|
        response = http.get(site.request_uri, @header)
		modified = Time.parse(response["last-modified"]).getlocal unless response["last-modified"].nil?
        if disp_error(response) == true
          return (if returnAsObj then [response.body, modified] else response.body end)
        else
          return false
        end
      end
    rescue Errno::ETIMEDOUT, TimeoutError
      puts 'Timeout Error. Retry.'
      retry
    end
  end

  #word  : 検索語
  #s_mode: 検索モード
  #users : ユーザ数閾値
  def search(word, s_mode, users)
    save_dir = make_dir(word)

    /検索結果：(\d+)件/ =~ get_file("http://www.pixiv.net/search.php?word=#{URI.encode(word)}&s_mode=#{s_mode}")
    start_p = 1
    goal_p = $1.to_i / 20 + 1
    puts "Total Images: #{$1}"
    puts "Total Pages : #{goal_p}"

    for p in start_p..goal_p
      page = get_file("http://www.pixiv.net/search.php?word=#{URI.encode(word)}&s_mode=#{s_mode}&p=#{p}")
      page.scan(/"(http:\/\/.+\.pixiv\.net\/img\/.+\/(\d+_s\..{3}))".+?\s.+?\s.+?(\d+) users/) do |uri, id, user|
        if user.to_i >= users
          uri.sub!(/_s/, ''); id.sub!(/_s/, '')
          if data = get_file(uri)
            save_file(data, "#{save_dir}/#{user}_#{id}")
          end
        end
      end
    end
  end

  #bookmarkの指定したページ番号に含まれるイラストを全て保存
  #保存したイラストの枚数を返す（漫画も1つで1枚とカウント）
  def getBookmark(dest_dir, page)
    savedCount = 0
    save_dir = make_dir(dest_dir)
    page = get_file("http://www.pixiv.net/bookmark.php?p=#{page}")
    exit unless page
    page.scan(/"(http:\/\/.+\.pixiv\.net\/img\/([^\/]+)\/)(\d+_s\.[a-zA-Z]+)"/) do |uri, username, id|
      id.sub!(/_s/, '')
      dest = "#{save_dir}/#{username}_#{id}"
      unless File.exists?(dest)
        if data = get_file(uri + id, true)
          save_file(data[0], dest, data[1])
          savedCount = savedCount + 1
		else
          puts "イラストが取得できなかったのでマンガモードで取得してみます"
          savedPages = manga(save_dir, id.to_i.to_s)
          puts "マンガを#{savedPages}ページ取得しました"
          if(savedPages > 0) then savedCount = savedCount + 1 end
        end
      end
    end
    savedCount
  end

  #bookmarkの最新ページからページを遡り全てのイラストを保存
  def manga(save_dir, illust_id)
    savedCount = 0
    page = get_file("http://www.pixiv.net/member_illust.php?mode=manga&illust_id=#{illust_id}")
    page.scan(/'(http:\/\/[^']+\.pixiv\.net\/img\/([^\/']+)\/)(\d+_p\d+\.[a-zA-z]+)'/) do |uri, username, id|
      dest = "#{save_dir}/#{username}_#{id}"
      unless File.exists?(dest)
        if data = get_file(uri + id.sub("_p","_big_p"), true)
        save_file(data[0], dest, data[1])
        savedCount = savedCount + 1
        end
      end
    end
    return savedCount
  end

  def bookmark(dest_dir)
    countAll = 0
    page = 1
    while true do
      puts "bookmarkの#{page}ページ目を取得します"
      savedCount = getBookmark(dest_dir, page)
      puts "#{savedCount}個の項目を保存しました"
      countAll += savedCount
      break if savedCount == 0
      page = page + 1;
    end
    countAll
  end

  #タグ検索
  def search_tag(word, users)
    search(word, 's_tag', users)
  end

  #タイトル・キャプション検索
  def search_title(word, users)
    search(word, 's_tc', users)
  end

  #ファイル保存
  def save_file(data, filename, modified)
    puts "save #{filename}"
    open(filename, 'wb') do |f|
      f.write data
    end
	`touch -d \"#{modified}\" \"#{filename}\"` if modified
  end

  #ディレクトリ作成
  def make_dir(name)
    if /mswin(?!ce)|mingw|cygwin|bccwin/ =~ RUBY_PLATFORM.downcase
      save_dir = "#{name.tosjis}"
    else
      save_dir = "#{name}"
    end
    if File.exist?(save_dir)
#      puts "Directory exist"
    else
      Dir.mkdir(save_dir)
    end
    return save_dir
  end


  private
  #Cookie取得
  def get_cookie(pixiv_id, pixiv_pass, user_agent, referer)
    begin
      Net::HTTP.start('www.pixiv.net', 80) do |http|
        response = http.post('/index.php',
                             "mode=login&pixiv_id=#{pixiv_id}&pass=#{pixiv_pass}",
                             'User-Agent' => user_agent
                            )
        if disp_error(response) == true
          cookie = response['Set-Cookie'].split(',')
          @header = {
            'User-Agent' => user_agent,
            'Referer'    => referer,
            'Cookie'     => cookie[-2] + ", " + cookie[-1]
          }
          return true
        else
          return false
        end
      end
    rescue Errno::ETIMEDOUT, TimeoutError
      puts 'Timeout Error. Retry.'
      retry
    end
  end

  #Error表示
  def disp_error(response)
    case response
    when Net::HTTPBadRequest
      puts 'Error 400'
    when Net::HTTPUnauthorized
      puts 'Error 401'
    when Net::HTTPForbidden
      puts 'Error 403'
    when Net::HTTPNotFound
      puts 'Error 404'
    when Net::HTTPInternalServerError
      puts 'Error 500'
    when Net::HTTPServiceUnavailable
      puts 'Error 503'
    else
      return true
    end
    return false
  end
end

def example
  config = YAML::load_file(ARGV[0])
  pixiv = AccessPixiv.new(config['pixiv']['id'], config['pixiv']['pass'],
                          config['pixiv']['user_agent'], config['pixiv']['referer'])
  pixiv.search_tag(ARGV[1].toutf8, ARGV[2].to_i)
end
#example()

