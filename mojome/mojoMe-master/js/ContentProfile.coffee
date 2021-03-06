class ContentProfile extends Class
	constructor: ->
		@post_list = null
		@activity_list = null
		@user_list = null
		@auth_address = null
		@user = new User()
		@activity_list = new ActivityList()
		@owned = false
		@need_update = true
		@filter_post_id = null
		@loaded = false
		@help_distribute = false

	renderNotSeeded: =>
		return h("div#Content.center.#{@auth_address}", [
			h("div.col-left", [
				h("div.users", [
					h("div.user.card.profile", [
						@user.renderAvatar()
						h("a.name.link",
							{href: @user.getLink(), style: "color: #{Text.toColor(@user.row.auth_address)}", onclick: Page.handleLinkClick},
							@user.row.user_name
						),
						h("div.cert_user_id", @user.row.cert_user_id)
						h("div.intro-full",
							@user.row.intro
						),
						h("div.follow-container", [
							h("a.button.button-follow-big", {href: "#", onclick: @user.handleFollowClick, classes: {loading: @user.submitting_follow}},
								h("span.icon-follow", "+"),
								if @user.isFollowed() then "Unfollow" else "Follow"
							)
						])
					])
				])
			]),
			h("div.col-center", {style: "padding-top: 30px; text-align: center"}, [
				h("h1", "Download profile site"),
				h("h2", "User's profile site not loaded to your client yet."),
				h("a.button.submit", {href: "#Add+site", onclick: @user.handleDownloadClick}, "Download user's site")
			])
		])

	setUser: (@hub, @auth_address) =>
		@loaded = false
		@log "setUser", @hub, @auth_address
		if not @post_list or @post_list.directories[0] != "data/users/"+@auth_address
			# Changed user, create clean status objects
			# @post_create = new PostCreate()
			@post_list = new PostList()
			@activity_list = new ActivityList()
			@user_list = new UserList()
			@user = new User()
			@post_list.directories = ["data/users/"+@auth_address]
			@user_list.followed_by = @user
			@user_list.limit = 50
			@need_update = true
		@

	findUser: (user_name, cb) =>
		query = """
			SELECT
			 json.cert_user_id,
			 REPLACE(REPLACE(json.directory, 'data/userdb/', ''), 'data/users/', '') AS auth_address,
			 CASE WHEN user.hub IS NOT NULL THEN user.hub ELSE json.site END AS hub,
			 user.*
			FROM
			 json
			LEFT JOIN user USING (json_id)
			WHERE user.user_name = :user_name OR json.user_name = :user_name
			ORDER BY date_added DESC LIMIT 1
		"""
		Page.cmd "dbQuery", [query, {user_name: user_name}], (res) =>
			user = new User()
			user.setRow(res[0])
			cb(user)

	filter: (post_id) =>
		@log "Filter", post_id
		@filter_post_id = post_id
		@need_update = true

	handleIntroSave: (intro, cb) =>
		@user.row.intro = intro
		@user.getData @user.hub, (data) =>
			data.intro = intro
			@user.save data, @user.hub, (res) =>
				cb(res)
				@update()

	handleUserNameSave: (user_name, cb) =>
		@user.row.user_name = user_name
		@user.getData @user.hub, (data) =>
			data.user_name = user_name
			@user.save data, @user.hub, (res) =>
				cb(res)
				@update()

	handleAvatarUpload: (image_base64uri) =>
		# Cleanup previous avatars
		Page.cmd "fileDelete", @user.getPath()+"/avatar.jpg"
		Page.cmd "fileDelete", @user.getPath()+"/avatar.png"

		if not image_base64uri
			# Delete image
			@user.getData @user.hub, (data) =>
				data.avatar = "generate"
				@user.save data, @user.hub, (res) =>
					Page.cmd "wrapperReload"  # Reload the page
			return false

		# Handle upload
		image_base64 = image_base64uri?.replace(/.*?,/, "")
		ext = image_base64uri.match("image/([a-z]+)")[1]
		if ext == "jpeg" then ext = "jpg"


		Page.cmd "fileWrite", [@user.getPath()+"/avatar."+ext, image_base64], (res) =>
			@user.getData @user.hub, (data) =>
				data.avatar = ext
				@user.save data, @user.hub, (res) =>
					Page.cmd "wrapperReload"  # Reload the page

	handleOptionalHelpClick: =>
		if Page.server_info.rev < 1700
			Page.cmd "wrapperNotification", ["info", "You need mojoNet version 0.5.0 use this feature"]
			return false

		@user.hasHelp (optional_helping) =>
			@optional_helping = optional_helping
			if @optional_helping
				Page.cmd "OptionalHelpRemove", ["data/users/#{@user.auth_address}", @user.hub]
				@optional_helping = false
			else
				Page.cmd "OptionalHelp", ["data/users/#{@user.auth_address}", "#{@user.row.user_name}'s new files", @user.hub]
				@optional_helping = true
			Page.content_profile.update()
			Page.projector.scheduleRender()
		return true

	render: =>
		if @need_update
			@log "Updating"
			@need_update = false

			# Update components
			@post_list.filter_post_ids = if @filter_post_id then [@filter_post_id] else null
			@post_list?.need_update = true
			@user_list?.need_update = true
			@activity_list?.need_update = true
			@activity_list.directories = ["data/users/#{@auth_address}"]

			# Update profile details
			@user.auth_address = @auth_address
			@user.hub = @hub
			@user.get @hub, @auth_address, (res) =>
				if res
					@owned = @user.auth_address == Page.user?.auth_address
					if @owned and not @editable_intro
						@editable_intro = new Editable("div", @handleIntroSave)
						@editable_intro.render_function = Text.renderMarked
						@editable_user_name = new Editable("span", @handleUserNameSave)
						@uploadable_avatar = new Uploadable(@handleAvatarUpload)
						@uploadable_avatar.try_png = true
						@uploadable_avatar.preverse_ratio = false
						@post_create = new PostCreate()
					Page.projector.scheduleRender()
					@loaded = true
				else
					Page.queryUserdb @auth_address, (row) =>
						@log "UserDb row", row
						@user.setRow(row)
						Page.projector.scheduleRender()
						@loaded = true


			if not Page.merged_sites[@hub]
				# Not seeded user, get details from userdb
				Page.queryUserdb @auth_address, (row) =>
					@user.setRow(row)
					Page.projector.scheduleRender()
					@loaded = true

			@user.hasHelp (res) =>
				@optional_helping = res

		if not @user?.row?.cert_user_id
			if @loaded
				return h("div#Content.center.#{@auth_address}", [h("div.user-notfound", "User not found or muted")])
			else
				return h("div#Content.center.#{@auth_address}", [])

		if not Page.merged_sites[@hub]
			return @renderNotSeeded()

		if @post_list.loaded and not Page.on_loaded.resolved then Page.on_loaded.resolve()

		h("div#Content.center.#{@auth_address}", [
			h("div.col-left", {classes: {faded: @filter_post_id}}, [
				h("div.users", [
					h("div.user.card.profile", {classes: {followed: @user.isFollowed()}}, [
						if @owned then @uploadable_avatar.render(@user.renderAvatar) else @user.renderAvatar()
						h("span.name.link",
							{style: "color: #{Text.toColor(@user.row.auth_address)}"},
							if @owned
								@editable_user_name.render(@user.row.user_name)
							else
								h("a", {href: @user.getLink(), style: "color: #{Text.toColor(@user.row.auth_address)}", onclick: Page.handleLinkClick}, @user.row.user_name)
						),
						h("div.cert_user_id", @user.row.cert_user_id)
						if @owned
							h("div.intro-full", @editable_intro.render(@user.row.intro))
						else
							h("div.intro-full", {innerHTML: Text.renderMarked(@user.row.intro)})
						h("div.follow-container", [
							h("a.button.button-follow-big", {href: "#", onclick: @user.handleFollowClick},
								h("span.icon-follow", "+"),
								if @user.isFollowed() then "Unfollow" else "Follow"
							)
						]),
						h("div.help.checkbox", {classes: {checked: @optional_helping}, onclick: @handleOptionalHelpClick},
							h("div.checkbox-skin"),
							h("div.title", "Help distribute this user's images")
						)
					])
				]),
				h("a.user-mute", {href: "#Mute", onclick: @user.handleMuteClick},
					h("div.icon.icon-mute"),
					"Mute #{@user.row.cert_user_id}"
				),
				@activity_list.render(),
				if @user_list.users.length > 0
					h("h2.sep", {afterCreate: Animation.show}, [
						"Following",
					])
				@user_list.render(".gray"),
			]),
			h("div.col-center", [
				if @owned and not @filter_post_id
					h("div.post-create-container", {enterAnimation: Animation.slideDown, exitAnimation: Animation.slideUp}, @post_create.render())
				@post_list.render()
				#if @filter_post_id
				#	h("a.more.small", {style: "color: #AAA", key: "all", href: @user.getLink(), onclick: Page.handleLinkClick, enterAnimation: Animation.slideDown, exitAnimation: Animation.slideUp}, "Show more posts by this user...")
			])
		])

	update: =>
		if not @auth_address
			return
		@need_update = true
		Page.projector.scheduleRender()

window.ContentProfile = ContentProfile