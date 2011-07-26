load './pixiv.rb'
#require '/home/root/gageasbot'

class PixivBookmarkSync
	def PixivBookmarkSync.main
		config = YAML::load_file(ARGV[0]);
		pixiv = AccessPixiv.new(
			config['pixiv']['id'], 
			config['pixiv']['pass'],
			config['pixiv']['user_agent'], 
			config['pixiv']['referer']
		)
		count = pixiv.bookmark(config['pixiv']['dest_dir'])
#		botupdate("[INFO]PixivSync saved #{count} files")
	end
end
PixivBookmarkSync.main
