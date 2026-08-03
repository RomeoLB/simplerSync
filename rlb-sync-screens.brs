'03/08/26 - RLB - Plugin for sync screen playback - Cleaned-up
'Disable enhanced sync in BACon pres to use this plugin
'SyncScreenPlayback - plugin name
'plugin filename - rlb-sync-screens.brs
'upload-v9
'supports both DP and video file in Medialist

Function SyncScreenPlayback_Initialize(msgPort As Object, userVariables As Object, bsp as Object)

   ' print "SyncScreenPlayback_Initialize - entry"
   ' print "type of msgPort is ";type(msgPort)
    'print "type of userVariables is ";type(userVariables)

    SyncScreenPlayback = newSyncScreenPlayback(msgPort, userVariables, bsp)
	
    return SyncScreenPlayback
End Function



Function newSyncScreenPlayback(msgPort As Object, userVariables As Object, bsp as Object)
	
	print "initSyncScreenPlayback Plugin"

	' Create the object to return and set it up
	
	s = {}
	s.msgPort = msgPort
	s.userVariables = userVariables
	s.bsp = bsp
	s.ProcessEvent = SyncScreenPlayback_ProcessEvent
	s.PluginSendMessage = PluginSendMessage
	s.PluginSendZonemessage = PluginSendZonemessage
	s.registrySection = CreateObject("roRegistrySection", "networking")
	s.sTime = createObject("roSystemTime")
	' s.ImageTimer=CreateObject("roTimer")
	' s.ImageTimer.SetPort(s.msgPort)
	s.vm = CreateObject("roVideoMode")
	s.PluginSystemLog = CreateObject("roSystemLog")		
	s.HandleTimerEventPlugin = HandleTimerEventPlugin
	s.HandlePluginUDPEvent = HandlePluginUDPEvent
	s.HandlePluginMessageEvent = HandlePluginMessageEvent
	s.HandlePluginroAssetFetcherEvent = HandlePluginroAssetFetcherEvent
	s.PluginConfigDevice = PluginConfigDevice
	s.PlayfilesFromStorageMedia = PlayfilesFromStorageMedia
	s.PlayFileInSync = PlayFileInSync
	s.HandlePluginSyncEvent = HandlePluginSyncEvent
	s.StartDelayedCheckTimer = StartDelayedCheckTimer
    s.StartDelayTimer = StartDelayTimer
	s.StartLaterCheckTimer = StartLaterCheckTimer
	's.CheckDownloadFeed = CheckDownloadFeed
	s.PluginPlayListBuilder = PluginPlayListBuilder
	s.SetupSyncManager = SetupSyncManager
	s.StartDelayLoadFeedTimer = StartDelayLoadFeedTimer
	s.SyncParam = SyncParam
	s.BuildPluginPlayers = BuildPluginPlayers
	s.ApplyLoopMode = ApplyLoopMode
	s.PluginCleanUpOnTransition = PluginCleanUpOnTransition
	s.InitSyncTimingLog = InitSyncTimingLog
	s.WriteSyncTimingEntry = WriteSyncTimingEntry
	s.StartRebootTimer = StartRebootTimer
	s.StartSyncWatchdogTimer = StartSyncWatchdogTimer
	s.LogPtpStatus = LogPtpStatus
	s.HandlePtpEvent = HandlePtpEvent
	s.StartPtpPollTimer = StartPtpPollTimer
	s.Multiscreen_Mode_Enabled = true
	s.seamlessLooping = 0

	s.Player_is_Master = false
    s.ScreenPlaylist = []
    s.playlistIndex = 0

	di = CreateObject("roDeviceInfo")
	model$ = di.GetModel()
	serialNumber$ = di.GetDeviceUniqueId()
	shortSerialNumber$ = Right(serialNumber$, 4)
	s.deviceName$ = model$ + "-" + shortSerialNumber$
	di = invalid
	print "DeviceName: " + s.deviceName$
	's.FeednameListPlugin = []

	s.IndexTracker = -1
	s.StartImageTimer = StartImageTimer
	s.ImageTimerTimeout = 6
	's.targetFeedID = invalid

	'autorun checked variable
	s.bsp.pluginSyncOverride = "SyncScreenPlayback"

	' Sync watchdog — reinitialises roSyncManager if no sync event arrives within the timeout.
	' Applies to all players: both leader and slaves can lose their roSyncManager after a
	' network dropout even after PTP recovers. Leader gets an extra kick (PlayfilesFromStorageMedia)
	' because no one else will restart its Synchronize() cycle.
	s.syncWatchdogTimeout = 90    ' seconds — ~3x the expected clip duration
	s.syncWatchdogResetCount = 0  ' reinit attempts since last good sync event
	s.syncWatchdogMaxResets = 2   ' reinit twice before falling back to reboot

	' PTP monitoring state — seeded at startup from roPtp.GetPtpStatus(), then updated
	' on each roPtpEvent so HandlePtpEvent can report how long the previous state was held.
	s.ptpCurrentState$ = ""
	s.ptpStateChangedAt = 0

	' Sync timing log state — tracks receive time and playing time for 3 playlist loops
	s.syncLoggingActive = false   ' enabled by InitSyncTimingLog after master/slave role is known
	s.syncLoopCount = 0           ' number of complete loops logged so far
	s.syncMaxLoops = 3
	s.syncLastFileIndex = -1      ' previous sync ID; -1 = not yet seen any
	s.syncEventReceiveTime$ = ""      ' timestamp captured when roSyncManagerEvent arrives
	s.syncCurrentSyncId = -1          ' file index from the current sync event
	s.syncCurrentIsoTimestamp$ = ""   ' SyncIsoTimestamp from the sync event (PTP target start time)
	s.logFileName$ = ""

	s.StartDelayTimer()

	return s
End Function


	
Function SyncScreenPlayback_ProcessEvent(event As Object) as boolean

	retval = false
	print "SyncScreenPlayback_ProcessEvent - entry"
   	print "type of m is ";type(m)
   	print "type of event is ";type(event)

	if type(event) = "roControlDown" then
			
		'retval = HandlePluginGPIOEvent(event, m)
	
	else if type(event) = "roAssociativeArray" then
		
		if type(event["EventType"]) = "roString"
			print ""
			print " @@@ EventType @@@ "; event["EventType"]
			print ""
			if event["EventType"] = "EVENT_PLUGIN_MESSAGE" then
				if event["PluginName"] = "SyncScreenPlayback" then
					pluginMessage$ = event["PluginMessage"]	
					'retval = HandlePluginMessageEvent(pluginMessage$)
				end if
			
			else if event["EventType"] = "SEND_PLUGIN_MESSAGE" then
			
				if event["PluginName"] = "SyncScreenPlayback" then
					pluginMessage$ = event["PluginMessage"]
					m.HandlePluginMessageEvent(pluginMessage$)
				end if
				
			else if event["EventType"] = "USER_VARIABLES_UPDATED" then
				'stop
			else if event["EventType"] = "USER_VARIABLE_CHANGE" then

			else if event["EventType"] = "CONTENT_DATA_FEED_UNCHANGED" then	
				print ""
				print " @@@ CONTENT_DATA_FEED_UNCHANGED @@@ "
				print ""
				m.StartDelayLoadFeedTimer()
			else if event["EventType"] = "CONTENT_DATA_FEED_LOADED" then
				print ""
				print " @@@ CONTENT_DATA_FEED_LOADED @@@ "
				print ""
				m.StartDelayLoadFeedTimer()
			else if event["EventType"] = "PREPARE_FOR_RESTART" then	
				print ""
				print " @@@ PREPARE_FOR_RESTART @@@ "
				print ""
					
			end if
		end if
	else if type(event) = "roDatagramEvent" then
		retval = HandlePluginUDPEvent(event, m)
	else if type(event) = "roTimerEvent" then
		retval = HandleTimerEventPlugin(event, m)	
	else if type(event) = "roVideoEvent" then
		retval = HandlePluginVideoEvent(event, m)
	else if type(event) = "roAssetFetcherEvent" then
		retval = HandlePluginroAssetFetcherEvent(event, m)
	else if type(event) = "roHtmlWidgetEvent" then
		'retval = HandleHtmlWidgetEventPlugin(event, m)
	else if type(event) = "roStreamByteEvent" then
		'retval = HandleStreamByteEventPlugin(event, m)	
	else if type(event) = "roStreamLineEvent" then	
		'retval = HandleStreamEventPlugin(event, m)
	else if type(event) = "roUrlEvent" then	
		'retval = HandleUrlEventPlugin(event, m)
	else if type(event) = "roSyncManagerEvent" then
		retval = HandlePluginSyncEvent(event, m)
	else if type(event) = "roPtpEvent" then
		retval = HandlePtpEvent(event, m)
	else if type(event) = "roControlCloudMessageEvent" then
		print ""
		print " @@@ roControlCloudMessageEvent Received @@@ "
		print "UserData: "; event.GetUserData()
		ccloudData = event.GetData()
		print "Data: "; ccloudData
		if type(ccloudData) = "roString" or type(ccloudData) = "String" then
			payload = ParseJson(ccloudData)
			print "Parsed Payload: "; payload

			if type(payload) = "roAssociativeArray" then
				if payload.updateSettings = true or payload.updateSchedule = true then

					'presentation restart does not allow the presentation to update
					' print ""
					' print " @@@ updateSettings = true - forcing presentation restart @@@ "
					' print ""
					' m.bsp.Restart("")

					print ""
					print " @@@ updateSettings = true or payload.updateSchedule = true - forcing player reboot @@@ "
					print ""
					RebootSystem()
				end if					
			end if
		end if
		print ""
		retval = true
	end if
	
	return retval
End Function
	


Function HandlePluginroAssetFetcherEvent(origMsg as Object, m as Object) as boolean

	retval = false
	userData$ = origMsg.GetUserData()
	currentEvent = origMsg.GetEvent()

	print ""
	print " *********** roAssetFetcherEvent userData$  ****************  " userData$
	print " *********** roAssetFetcherEvent  currentEvent ****************  " currentEvent
	print ""
	
	if currentEvent = 2 then
		print ""
		print "@@@ Feed fully downloaded @@@ ";
		print ""
		'm.First_CONTENT_DATA_FEED_UNCHANGED = false
		'm.CheckDownloadFeed(userData$)
	end if 
	
	return retval
End Function



Function HandlePluginUDPEvent(origMsg as Object, m as Object) as boolean

	print "UDP Message Received in plugin - "; origMsg

	if origMsg = "SyncMe" then
		print ""
		print "m.bsp.sign.zoneshsm[0].activestate.id$: "; m.bsp.sign.zoneshsm[0].activestate.id$
		print "m.bsp.sign.zoneshsm[1].activestate.id$: "; m.bsp.sign.zoneshsm[1].activestate.id$
		print ""
	else if origMsg = "SuperStart" then
		m.PluginCleanUpOnTransition()	
	else if origMsg = "Other" then
		m.PluginCleanUpOnTransition()	
	end if	
End Function



Function HandlePluginSyncEvent(origMsg as Object, m as Object) as boolean

	print "roSyncManagerEvent Message Received in plugin - "; origMsg
	if m.PluginSyncManager <> invalid then
		print "GetUserData from SyncManager: "; m.PluginSyncManager.GetUserData()
	end if	

	'stop

	retval = false

	userdata = invalid
	userdata = origMsg.GetUserData()
	if userdata <> invalid then
		if userdata.name = "rlb-sync-manager" then
			synchronizeEvent$ = origMsg.GetId()

			' Capture receive time immediately before any processing.
			' Detect loop wrap (syncId returning to 0 after a higher value) to track
			' how many complete playlist cycles have been logged.
			if m.syncLoggingActive = true then
				newSyncId = int((val(synchronizeEvent$)))
				if newSyncId = 0 and m.syncLastFileIndex >= 0 then
					m.syncLoopCount = m.syncLoopCount + 1
					print "SyncTimingLog: loop "; m.syncLoopCount; " complete"
					if m.syncLoopCount >= m.syncMaxLoops then
						m.syncLoggingActive = false
						print "SyncTimingLog: "; m.syncMaxLoops; " loops captured - logging stopped. Role: "; m.logFileName$
					end if
				end if
				m.syncLastFileIndex = newSyncId
				if m.syncLoggingActive = true then
					m.syncEventReceiveTime$ = m.sTime.GetLocalDateTime()
					m.syncCurrentSyncId = newSyncId
					m.syncCurrentIsoTimestamp$ = origMsg.GetIsoTimestamp()
				end if
			end if

			m.syncInfo = CreateObject("roAssociativeArray")
			m.syncInfo.SyncDomain = origMsg.GetDomain()
			m.syncInfo.SyncId = origMsg.GetId()
			m.syncInfo.SyncIsoTimestamp = origMsg.GetIsoTimestamp()

			m.currentFileName = m.syncInfo.lookup("SyncId")

			m.LogPtpStatus("sync-event=" + synchronizeEvent$)

			ok = m.PlayFileInSync(m.syncInfo)
			if ok then
				print "synchronizeEvent$: "; synchronizeEvent$ + " at: "; m.sTime.GetLocalDateTime()
				m.syncWatchdogResetCount = 0
				m.StartSyncWatchdogTimer()
				'stop
				retval = true
			end if
		end if
	end if
	print "HandlePluginSyncEvent - exit with retval: "; retval
	return retval
End Function



Function HandlePluginVideoEvent(origMsg as Object, m as Object) as boolean

	print "Video Message Received in plugin - "; origMsg
	'print "GetUserData from Video Player: "; m.PluginvideoPlayer.GetUserData()

	retval = false

	VideoPlayerEventReceived = origMsg.GetInt()

	userdata = invalid
	userdata = origMsg.GetUserData()
	if userdata <> invalid then
		if userdata.name = "rlb-sync-video-player" then	
			if VideoPlayerEventReceived = 8 then
				print "Video End Event Received at: ";m.sTime.GetLocalDateTime()
				if m.seamlessLooping = 1 then
					' Single-item playlist with SetLoopMode(1) applied (no audio track, or a
					' loop-safe audio codec per IsAudioCompatibleForSeamlessLoop) - the player
					' loops the file internally, so no restart is triggered here.
					print "Video End Event - SetLoopMode(1) active, not restarting playback"
				else if m.Player_is_Master = true then
					m.IndexTracker = m.IndexTracker + 1
					m.PlayfilesFromStorageMedia()
				end if
			else if VideoPlayerEventReceived = 3 then
				videoPlayingTime$ = m.sTime.GetLocalDateTime()
				print "Video playing Event Received at "; videoPlayingTime$
				if m.syncLoggingActive = true and m.syncEventReceiveTime$ <> "" then
					m.WriteSyncTimingEntry(m.syncCurrentSyncId, m.syncEventReceiveTime$, m.syncCurrentIsoTimestamp$, videoPlayingTime$)
					m.syncEventReceiveTime$ = ""
					m.syncCurrentIsoTimestamp$ = ""
				end if
			end if
			retval = true
		end if
	end if
	print "HandlePluginVideoEvent - exit with retval: "; retval
	return retval
End Function



Function HandleTimerEventPlugin(origMsg as Object, m as Object) as boolean

	timerIdentity = origMsg.GetSourceIdentity()

	if m.Player_is_Master = true then
		if type(m.ImageTimer) = "roTimer" then
			if m.ImageTimer.GetIdentity() = origMsg.GetSourceIdentity() then
				m.IndexTracker = m.IndexTracker + 1	
				m.PlayfilesFromStorageMedia()
				return true
			end if
		end if
	end if

	if type(m.DelayedCheckTimer) = "roTimer" then
		if m.DelayedCheckTimer.GetIdentity() = origMsg.GetSourceIdentity() then
			userData = origMsg.GetUserData()
			'print "FeedID: "; userData.FeedID
			'm.CheckCardForMediaFilesFromFeed(userData.FeedID)
			return true
		end if
	end if
	if type(m.LaterCheckTimer) = "roTimer" then
		if m.LaterCheckTimer.GetIdentity() = origMsg.GetSourceIdentity() then
			m.PluginPlayListBuilder()

			m.SetupSyncManager()
			m.BuildPluginPlayers()
			if m.Player_is_Master = true then
				m.PlayfilesFromStorageMedia()
			end if
			m.StartSyncWatchdogTimer()
			return true
		end if
	end if

    if type(m.DelayTimer) = "roTimer" then
		if m.DelayTimer.GetIdentity() = origMsg.GetSourceIdentity() then

			m.PluginConfigDevice()
			m.InitSyncTimingLog()
			m.StartLaterCheckTimer()

			m.PluginSystemLog.SendLine(" @@@ RLB - Plugin Version 3.0 for Screen Sync Playback @@@ ")

			' Subscribe to PTP state change events and log the initial state.
			m.ptpMonitor = CreateObject("roPtp")
			m.ptpMonitor.SetPort(m.msgPort)
			ptpInit = m.ptpMonitor.GetPtpStatus()
			if ptpInit <> invalid then
				m.ptpCurrentState$ = ptpInit.state
				m.ptpStateChangedAt = ptpInit.timestamp
			end if
			m.LogPtpStatus("startup")
			m.StartPtpPollTimer()

			' Subscribe to supervisor/cloud control messages (settings updates, group changes, etc.)
			' so they arrive on m.msgPort as roControlCloudMessageEvent.
			m.ccloud = CreateObject("roControlCloud")
			if m.ccloud <> invalid then
				m.ccloud.SetPort(m.msgPort)
				m.ccloud.SetUserData("rlb-sync-screens")
				m.ccloud.SendMessage({})
			end if

			return true
		end if
	end if
	if type(m.RebootDelayTimer) = "roTimer" then
		if m.RebootDelayTimer.GetIdentity() = origMsg.GetSourceIdentity() then
			print ""
			print "*** RebootDelayTimer fired - rebooting now ***"
			print ""
			RebootSystem()
			return true
		end if
	end if
	if type(m.SyncWatchdogTimer) = "roTimer" then
		if m.SyncWatchdogTimer.GetIdentity() = origMsg.GetSourceIdentity() then
			print ""
			print "*** SyncWatchdogTimer fired - no sync event in "; m.syncWatchdogTimeout; "s ***"
			print ""
			if m.seamlessLooping = 1 then
				' Single-item playlist under SetLoopMode(1) intentionally stops generating
				' sync events (see HandlePluginVideoEvent) - no sync event for a long time
				' is expected here, not a failure, so just rearm the watchdog.
				print "*** seamlessLooping active - no sync events expected, skipping reinit/reboot ***"
				m.StartSyncWatchdogTimer()
			else if m.syncWatchdogResetCount < m.syncWatchdogMaxResets then
				m.syncWatchdogResetCount = m.syncWatchdogResetCount + 1
				print "*** Reinitialising SyncManager (attempt "; m.syncWatchdogResetCount; " of "; m.syncWatchdogMaxResets; ") ***"
				m.SetupSyncManager()
				if m.Player_is_Master = true then
					m.PlayfilesFromStorageMedia()
				end if
				m.StartSyncWatchdogTimer()
			else
				print "*** SyncManager reinit failed after "; m.syncWatchdogMaxResets; " attempts - rebooting ***"
				m.StartRebootTimer()
			end if
			return true
		end if
	end if
	if type(m.PtpPollTimer) = "roTimer" then
		if m.PtpPollTimer.GetIdentity() = origMsg.GetSourceIdentity() then
			m.LogPtpStatus("poll")
			m.StartPtpPollTimer()
			return true
		end if
	end if
    if type(m.DelayLoadFeedTimer) = "roTimer" then
		if m.DelayLoadFeedTimer.GetIdentity() = origMsg.GetSourceIdentity() then
			if m.screenName$ <> invalid then 
				if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed <> invalid then
					if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.itemurls <> invalid then
						if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.itemurls.count() >= 0 then			
							m.PluginPlayListBuilder()
							if m.Player_is_Master = true then
								m.PlayfilesFromStorageMedia()
							end if						
						end if
					end if
				end if
			end if
			return true
		end if
	end if	
End Function
	


Function HandlePluginMessageEvent(origMsg as string)

	print ""
	print " @@@ HandlePluginMessageEvent: "; origMsg
	print ""

End Function



Function PluginCleanUpOnTransition()

	if m.PluginImagePlayer <> invalid then
		m.PluginImagePlayer.StopDisplay()
	end if
	if m.PluginvideoPlayer <> invalid then
		m.PluginvideoPlayer.StopClear()
	end if

	m.PluginvideoPlayer = invalid
	m.PluginImagePlayer = invalid
	m.PluginSyncManager = invalid
	m.syncManagerEvent = invalid
End Function


Function PluginSendMessage(Pmessage$ As String)

	pluginMessageCmd = CreateObject("roAssociativeArray")
	pluginMessageCmd["EventType"] = "EVENT_PLUGIN_MESSAGE"
	pluginMessageCmd["PluginName"] = "SyncScreenPlayback"
	pluginMessageCmd["PluginMessage"] = Pmessage$
	m.msgPort.PostMessage(pluginMessageCmd)
End Function



Sub PluginSendZonemessage(msg$ as String)
	' send ZoneMessage message
	zoneMessageCmd = CreateObject("roAssociativeArray")
	zoneMessageCmd["EventType"] = "SEND_ZONE_MESSAGE"
	zoneMessageCmd["EventParameter"] = msg$
	m.msgPort.PostMessage(zoneMessageCmd)
End Sub



Function StartDelayedCheckTimer(FeedID as String, TimeoutVal as integer)
    userdata = {}
    userdata.FeedID = FeedID
    userdata.TimeoutVal = TimeoutVal

    newTimeout = m.sTime.GetLocalDateTime()
    newTimeout.AddMilliseconds(TimeoutVal)
    m.DelayedCheckTimer = CreateObject("roTimer")
    m.DelayedCheckTimer.SetPort(m.msgPort)	
    m.DelayedCheckTimer.SetDateTime(newTimeout)
    m.DelayedCheckTimer.SetUserData(userdata)	
    ok = m.DelayedCheckTimer.Start()
End Function



Function PlayFileInSync(PlayParam as Object) As Boolean

	result = invalid
	playbackstarted = false

	if PlayParam <> invalid then

		fileindex$ = PlayParam.lookup("SyncId")
		fileindex% = int((val(fileindex$)))
		
		'if m.targetFeedID <> invalid AND m.FileList <> invalid then
		if m.ScreenPlaylist <> invalid then	
            if m.ScreenPlaylist[fileindex%] <> invalid then
                fullfilepath = m.ScreenPlaylist[fileindex%].path
				m.currentFileName = m.ScreenPlaylist[fileindex%].path
				PlayParam.AddReplace("Filename", fullfilepath)
				if m.ScreenPlaylist[fileindex%].type = "video" then
					print "PlayFileInSync - probeData for "; fullfilepath; ": "; m.ScreenPlaylist[fileindex%].probeData
					if type(m.ScreenPlaylist[fileindex%].probeData) = "roString" then
						PlayParam.AddReplace("ProbeString", m.ScreenPlaylist[fileindex%].probeData)
					end if
					if m.Multiscreen_Mode_Enabled = true then
						PlayParam.AddReplace("MultiscreenWidth", m.PluginMultiscreenWidth)
						PlayParam.AddReplace("MultiscreenHeight", m.PluginMultiscreenHeight)
						PlayParam.AddReplace("MultiscreenX", m.PluginMultiscreenX)
						PlayParam.AddReplace("MultiscreenY", m.PluginMultiscreenY)
						formatBezelx = int((m.PluginMultiscreenBezelX))
						formatBezely = int((m.PluginMultiscreenBezelY))
						m.vm.SetMultiscreenBezel(formatBezelx, formatBezely)
					end if
					m.ApplyLoopMode()
					result = m.PluginvideoPlayer.PlayFile(PlayParam)
				else if m.ScreenPlaylist[fileindex%].type = "image" then
					imagePath = PlayParam.Filename
					result = m.PluginvideoPlayer.PlayStaticImage(imagePath)
					m.StartImageTimer()
                end if 
			end if							
		end if
	end if	

	if result <> invalid then
		playbackstarted = true
	end if

	return playbackstarted
End Function


Sub SyncParam()

		m.currentFileName = m.ScreenPlaylist[m.IndexTracker].path
		indexedSyncId = stri(m.IndexTracker)

		if m.PluginSyncManager <> invalid then
			' RLB - Increased from 300ms to 1000ms. The 300ms window was too tight:
		' slave processing overhead is ~188ms and the live feed URL check can block
		' the event queue for ~400ms, causing sync events to be processed after the
		' PTP sync timestamp has already passed (slave misses the window and plays immediately).
		'm.syncManagerEvent = m.PluginSyncManager.Synchronize(indexedSyncId, 300)
		m.syncManagerEvent = m.PluginSyncManager.Synchronize(indexedSyncId, 1000) 'safer for all Series
		end if		

		print ""
		print "SyncParam - entry: "
		print "filename: "; m.currentFileName
		'print "m.targetFeedID: "; m.targetFeedID
		print "type(m.syncManagerEvent): "; type(m.syncManagerEvent)
		print "type(m.PluginSyncManager): "; type(m.PluginSyncManager)
		print "m.PluginSyncManager.GetCurrentConfig()"
		print m.PluginSyncManager.GetCurrentConfig()
		print "m.PluginSyncManager.GetUserData()"
		print m.PluginSyncManager.GetUserData()
		print ""
		
		if m.syncManagerEvent <> invalid then
			'm.aa.AddReplace("Filename", filename)
			m.aa.AddReplace("SyncDomain", m.syncManagerEvent.GetDomain())
			m.aa.AddReplace("SyncId", m.syncManagerEvent.GetId())
			m.aa.AddReplace("SyncIsoTimestamp", m.syncManagerEvent.GetIsoTimestamp())
			m.aa.AddReplace("FileIndex", m.IndexTracker)
		end if	

		'stop
		' if m.syncManagerEvent = invalid then
		' 	print "SyncManagerEvent is invalid"
		' 	print "m.SyncManager.GetCurrentConfig()"
		' 	print m.SyncManager.GetCurrentConfig()
		' 	print "m.SyncManager.GetCurrentConfig().master: "; m.SyncManager.GetCurrentConfig().master
		' end if
	'end if	
End Sub



' Searches every wall entry in the parsed sync-config.json array (ConfigFile) for the
' one whose "screens" map contains serialNumber, and returns that entry plus the
' matching screen name. Needed because sync-config.json holds configs for many walls -
' Returns invalid if no entry contains this serial number.
Function FindWallConfigForSerial(configFile as Object, serialNumber as String) as Object

	if configFile = invalid then return invalid

	for each entry in configFile
		if entry.screens <> invalid then
			for each screenName in entry.screens
				if entry.screens[screenName].serial = serialNumber then
					result = {}
					result.wallConfig = entry
					result.screenName = screenName
					return result
				end if
			end for
		end if
	end for

	return invalid

End Function



Sub PluginConfigDevice()


	rebootRequired = false
    m.screenName$ = ""
    presname$ = m.bsp.activepresentation$

	' Allow the config asset to be named either "sync-config.json" (simpler, checked
	' first) or "<presentationName>.json" (fallback, for presentations that already
	' name it that way).
	jsonPathinPool$ = m.bsp.assetPoolFiles.getPoolFilePath("sync-config.json")
	if jsonPathinPool$ = "" then
		jsonFilename$ = presname$ + ".json"
		jsonPathinPool$ = m.bsp.assetPoolFiles.getPoolFilePath(jsonFilename$)
	end if

	currentDrive$ = GetDefaultDrive()
	destinationFilePath$ = currentDrive$ + "sync-config.json"

	CopyFile(jsonPathinPool$, destinationFilePath$)

	if destinationFilePath$ <> "" then

		currentSyncConfigFile$ = ReadAsciiFile(destinationFilePath$)
		ConfigFile = ParseJson(currentSyncConfigFile$)

        print ""
        print "ConfigFile"
        print ConfigFile
        print ""

		di = CreateObject("roDeviceInfo")
		model = di.GetModel()
		print "Model: "; model
		serialNumber = di.GetDeviceUniqueId()
		print "This player's Serial Number: "; serialNumber

		wallConfig = invalid
		match = FindWallConfigForSerial(ConfigFile, serialNumber)
		if match <> invalid then
			wallConfig = match.wallConfig
			m.screenName$ = match.screenName
			print "Matched wall config: "; wallConfig.config_file
			print "Screen Name: "; m.screenName$
		else
			print ""
			print "**** No matching wall config found in sync-config.json for serial "; serialNumber; " ****"
			print ""
		end if

        if wallConfig <> invalid then
            m.ptpDomain$ = wallConfig.ptp_domain
            print "PTP Domain from JSON file: "; m.ptpDomain$
            m.ptp_interface$ = wallConfig.ptp_interface
            print "PTP Interface from JSON file: "; m.ptp_interface$
            m.Multiscreen_Mode_Enabled = wallConfig.multiscreen_mode_enabled
            print "Multiscreen Mode Enabled from JSON file: "; m.Multiscreen_Mode_Enabled
            ptpDomainInRegistry$ = m.registrySection.Read("ptp_domain")
            ptpInterfaceInRegistry$ = m.registrySection.Read("ptp_interface")

            if ptpDomainInRegistry$ = "" or ptpDomainInRegistry$ <> m.ptpDomain$ then	
            	Print"**** Writing ptp_domain to the Registry NOW ******"
            	m.registrySection.Write("ptp_domain", m.ptpDomain$)
            	rebootRequired = true
            end if

            if ptpInterfaceInRegistry$ = "" or ptpInterfaceInRegistry$ <> m.ptp_interface$ then	
            	Print"**** Writing ptp_interface to the Registry NOW ******"
				'wifi sync does not work - https://brightsign.atlassian.net/browse/OS-20946
            	' m.registrySection.Write("ptp_interface", m.ptp_interface$)
            	' rebootRequired = true
            end if

            if rebootRequired then
            	Print"Flush the registry and reboot the system..."
            	m.registrySection.Flush()
            	m.StartRebootTimer()
            endif

            if serialNumber = wallConfig.master_serial then
            	m.Player_is_Master = true
            	print "Player IS MASTER - Serial Number: "; serialNumber
                m.PluginSystemLog.sendline(" @@@ Player IS MASTER @@@ " + serialNumber)
				m.SetupSyncManager()
				setOK = m.PluginSyncManager.SetAsLeader(true)
				print ""
				print "SetAsLeader returned: "; setOK
				print ""			
            else 	
            	print ""
            	print "Player IS NOT MASTER - Serial Number: "; serialNumber
            	print ""				
                m.PluginSystemLog.sendline(" @@@ Player IS NOT MASTER @@@ " + serialNumber)
            end if

			if wallConfig.Multiscreen_Mode_Enabled = true then
				print ""
				print "Multiscreen Mode Enabled : "
				print ""
				m.Multiscreen_Mode_Enabled = true
				m.PluginMultiscreenWidth = wallConfig.screens[m.screenName$].MultiscreenWidth
				m.PluginMultiscreenHeight = wallConfig.screens[m.screenName$].MultiscreenHeight
				m.PluginMultiscreenX = wallConfig.screens[m.screenName$].MultiscreenX
				m.PluginMultiscreenY = wallConfig.screens[m.screenName$].MultiscreenY
				m.PluginMultiscreenBezelX = wallConfig.screens[m.screenName$].x_pct
				m.PluginMultiscreenBezelY = wallConfig.screens[m.screenName$].y_pct
				'crazy bezel values for testing multiscreen - these should be set to 0 for normal operation
				'm.vm.SetMultiscreenBezel(3, 8)
				'stop
			else if wallConfig.Multiscreen_Mode_Enabled = false then

				print ""
				print "Multiscreen Mode NOT Enabled : "
				print ""
				'stop
			end if	



            if rebootRequired then
				print ""
            	Print"Flush the registry and rebooting the system..."
				print ""
				'stop
            	m.registrySection.Flush()
            	m.StartRebootTimer()
            endif

            m.vm.SetSyncDomain(m.ptpDomain$)
            print "@@@ VSYNC Enabled @@@ "

			if m.bsp.sign.zoneshsm[0].statetable[m.screenName$] <> invalid then	
				if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].items <> invalid then
					if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].items.count() >= 0 then
						m.PluginPlayListBuilder()
					end if
				end if
			end if

        end if
    end if
End Sub



' Parses the pipe-delimited BrightAuthor probe string attached to a media item
' (e.g. "2|TT=MP4|IX=Y|AP=2|AC=AAC|ACH=2|ASR=48000|...") and returns true if the file
' has no audio track at all, or has one using a codec confirmed to loop cleanly under
' SetLoopMode(1). Files with an incompatible (or unconfirmed) audio track fall back to
' SetLoopMode(0) with an explicit PlayFile restart on every loop instead.
' AAC is confirmed NOT to loop cleanly - do not add it here. Add a codec to
' COMPATIBLE_AUDIO_CODECS only once testing has actually confirmed it loops cleanly.
Function IsAudioCompatibleForSeamlessLoop(probeData as Object) as boolean

	if type(probeData) <> "roString" and type(probeData) <> "String" then return true

	' Find the "|AC=...|" field manually via Instr/Mid. Padding with leading/trailing
	' "|" lets the same search handle AC= appearing as the first or last field too.
	audioCodec$ = ""
	searchString$ = "|" + probeData + "|"
	acFieldStart% = Instr(1, searchString$, "|AC=")
	if acFieldStart% > 0 then
		valueStart% = acFieldStart% + 4
		valueEnd% = Instr(valueStart%, searchString$, "|")
		audioCodec$ = UCase(Mid(searchString$, valueStart%, valueEnd% - valueStart%))
	end if

	' no "AC=" field present means no audio track - safe to loop
	if audioCodec$ = "" then return true

	COMPATIBLE_AUDIO_CODECS = []
	for each codec in COMPATIBLE_AUDIO_CODECS
		if audioCodec$ = codec then return true
	next

	return false

End Function



Function PluginPlayListBuilder()

	print ""
	print "PluginPlayListBuilder - entry"
	print ""

	m.ScreenPlaylist = []

	if m.bsp.sign.zoneshsm[0].statetable[m.screenName$] <> invalid then	
		if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].items <> invalid then
			if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].items.count() >= 0 then
				print "Items in the statetable for the screen: "; m.screenName$; " are: "
				if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].populatefrommedialibrary = true then
					for each item in m.bsp.sign.zoneshsm[0].statetable[m.screenName$].items
						print "Item: "; item
						print "Type: "; item.type
						print "Filename: "; item.filename$
						filepath$ = m.bsp.assetPoolFiles.getPoolFilePath(item.filename$)
						print "Filepath: "; filepath$
						m.ScreenPlaylist.push({filename: item.filename$, path: filepath$, type: item.type, probeData: item.probeData})
						m.playlistIndex = m.playlistIndex + 1
					next					
				end if	
			end if
		else if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed <> invalid then
			'stop
			'm.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.id$
			m.screenFeedID$ = m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.id$
			if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.itemurls <> invalid then
				if m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.itemurls.count() >= 0 then
					print "Items in the livedatafeed for the screen: "; m.screenName$; " are: "
					itemindex = 0
					for each itemurl in m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.itemurls
						print "Item URL: "; itemurl
						filename$ = m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.filekeys[itemindex]
						filepath$ = m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.assetPoolFiles.getPoolFilePath(itemurl)
						filetype$ = m.bsp.sign.zoneshsm[0].statetable[m.screenName$].livedatafeed.filetypes[itemindex]
						print "Filepath: "; filepath$
						'stop
						m.ScreenPlaylist.push({filename: filename$, path: filepath$, type: filetype$})
						m.playlistIndex = m.playlistIndex + 1
						itemindex = itemindex + 1
					next
				end if
			end if		
		end if	
	end if	

	print ""
	print "PluginPlayListBuilder - size of playlist: "; m.ScreenPlaylist.count()
	print "PluginPlayListBuilder - playlist content: "; m.ScreenPlaylist 	
	print ""

	if m.ScreenPlaylist.count() > 0 then
		for each plitem in m.ScreenPlaylist
			print "Item: "; plitem
			print "Item type: "; plitem.type
			print "Item filename: "; plitem.filename
			print "Item path: "; plitem.path
		next

		previousSeamlessLooping = m.seamlessLooping
		if m.ScreenPlaylist.count() = 1 and IsAudioCompatibleForSeamlessLoop(m.ScreenPlaylist[0].probeData) then
			'single-item playlist with no audio track or a loop-safe audio codec -
			'enable seamless looping (SetLoopMode(1), no restart) so it repeats without a gap
			m.seamlessLooping = 1
		else
			'multi-item playlist, or single item with an audio codec that loops erratically -
			'disable seamless looping (SetLoopMode(0)) and restart via PlayFile on every loop
			m.seamlessLooping = 0
		end if

		if m.seamlessLooping <> previousSeamlessLooping and m.PluginvideoPlayer <> invalid then
			print ""
			print "PluginPlayListBuilder - seamlessLooping changed to "; m.seamlessLooping; " - restarting video player"
			print ""
			m.ApplyLoopMode()
			m.PluginvideoPlayer.StopClear()
			m.IndexTracker = -1
			if m.Player_is_Master = true then
				m.PlayfilesFromStorageMedia()
			end if
		end if
	else if m.ScreenPlaylist.count() = 0 then
		print "Playlist is empty"
		m.ScreenPlaylist = []
	end if
End Function



Function StartImageTimer()
	
	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(m.ImageTimerTimeout)
	m.ImageTimer=CreateObject("roTimer")
	m.ImageTimer.SetPort(m.msgPort)
	m.ImageTimer.SetDateTime(newTimeout)
	m.ImageTimer.Start()
End Function



Function PlayfilesFromStorageMedia()

	print ""
	print "PlayfilesFromStorageMedia - entry: "
	print "m.ScreenPlaylist.count(): "; m.ScreenPlaylist.count()
	print "m.IndexTracker: "; m.IndexTracker
	print ""

	'stop
	if m.ScreenPlaylist.count() <> invalid then
		if m.ScreenPlaylist.count() > 0 then
			
			if m.IndexTracker = -1 or m.IndexTracker = m.ScreenPlaylist.count() then			
				m.IndexTracker = 0				
			end if
			
			if m.IndexTracker <= m.ScreenPlaylist.count() then
				'stop
				if m.ScreenPlaylist[m.IndexTracker].type = "video" then		
					if m.Player_is_Master = true then
						m.SyncParam()
					end if
				else if m.ScreenPlaylist[m.IndexTracker].type = "image" then

					if m.Player_is_Master = true then				
						m.SyncParam()
						m.StartImageTimer()
					end if											
				end if					
			end if
		end if
	end if	
	'return ok
End Function



Function StartDelayTimer()

	print "StartDelayTimer..."
	
	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(1)
	m.DelayTimer = CreateObject("roTimer")
	m.DelayTimer.SetPort(m.msgPort)
	m.DelayTimer.SetDateTime(newTimeout)
	m.DelayTimer.Start()
End Function



Function StartLaterCheckTimer()

	print "StartLaterCheckTimer..."
	
	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(5)
	m.LaterCheckTimer = CreateObject("roTimer")
	m.LaterCheckTimer.SetPort(m.msgPort)
	m.LaterCheckTimer.SetDateTime(newTimeout)
	m.LaterCheckTimer.Start()
End Function


Function StartDelayLoadFeedTimer()

	print "StartDelayLoadFeedTimer..."

	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(10)
	m.DelayLoadFeedTimer = CreateObject("roTimer")
	m.DelayLoadFeedTimer.SetPort(m.msgPort)
	m.DelayLoadFeedTimer.SetDateTime(newTimeout)
	m.DelayLoadFeedTimer.Start()
End Function



' Waits 15 seconds then calls RebootSystem(). Using a timer instead of sleep()
' keeps the event loop alive during the delay so no events are dropped.
Sub StartRebootTimer()
	print ""
	print "*** Rebooting in 15 seconds... ***"
	print ""
	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(15)
	m.RebootDelayTimer = CreateObject("roTimer")
	m.RebootDelayTimer.SetPort(m.msgPort)
	m.RebootDelayTimer.SetDateTime(newTimeout)
	m.RebootDelayTimer.Start()
End Sub



' Restarted on every successful sync event. If it fires, roSyncManager has gone silent —
' reinitialise it (and kick PlayfilesFromStorageMedia on the leader) rather than freezing.
Function StartSyncWatchdogTimer()
	print "StartSyncWatchdogTimer..."
	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(m.syncWatchdogTimeout)
	m.SyncWatchdogTimer = CreateObject("roTimer")
	m.SyncWatchdogTimer.SetPort(m.msgPort)
	m.SyncWatchdogTimer.SetDateTime(newTimeout)
	m.SyncWatchdogTimer.Start()
End Function




' Queries roPtp and prints the current PTP state with timing context to the player log.
' context$ is a short label (e.g. "startup", "poll", "sync-event=0") shown in each line.
Sub LogPtpStatus(context$ as string)
	if m.ptpMonitor = invalid then return
	status = m.ptpMonitor.GetPtpStatus()
	if status = invalid then
		msg$ = "PTP [" + context$ + "]: status unavailable"
		print msg$
		m.PluginSystemLog.SendLine(msg$)
		return
	end if
	state$ = status.state
	changedAt = status.timestamp
	now = uptime(0)
	inStateSecs = int(now - changedAt)
	if m.Player_is_Master = true then
		role$ = "sync-leader"
	else
		role$ = "slave"
	end if
	line1$ = "--- PTP [" + context$ + "] uptime=" + str(int(now)) + "s ---"
	line2$ = "  state  : " + state$
	line3$ = "  since  : uptime " + str(int(changedAt)) + "s  (" + str(inStateSecs) + "s in state)"
	line4$ = "  role   : " + role$
	line5$ = "---"
	print ""
	print line1$
	print line2$
	print line3$
	print line4$
	print line5$
	print ""
	m.PluginSystemLog.SendLine(line1$)
	m.PluginSystemLog.SendLine(line2$)
	m.PluginSystemLog.SendLine(line3$)
	m.PluginSystemLog.SendLine(line4$)
	m.PluginSystemLog.SendLine(line5$)
End Sub



' Handles roPtpEvent — fired by roPtp whenever PTP state changes.
' Logs the transition and how long the previous state was held, which is the key
' data for diagnosing boot-order and grandmaster-discovery timing problems.
Function HandlePtpEvent(origMsg as Object, m as Object) as boolean
	status = origMsg.GetPtpStatus()
	newState$ = status.state
	changedAt = status.timestamp
	prevDuration = int(changedAt - m.ptpStateChangedAt)
	line1$ = "*** PTP STATE CHANGE @ uptime " + str(int(changedAt)) + "s ***"
	line2$ = "  " + m.ptpCurrentState$ + " -> " + newState$ + "  (previous state held ~" + str(prevDuration) + "s)"
	if newState$ = "slave" then
		line3$ = "  SLAVE: clock locked to grandmaster — sync timing is reliable from here"
	else if newState$ = "uncalibrated" then
		line3$ = "  UNCALIBRATED: calibrating to grandmaster — sync timing may be unreliable"
	else if newState$ = "master" then
		line3$ = "  MASTER: this player is grandmaster — no external PTP clock source"
	else
		line3$ = "  state: " + newState$
	end if
	print ""
	print line1$
	print line2$
	print line3$
	print ""
	m.PluginSystemLog.SendLine(line1$)
	m.PluginSystemLog.SendLine(line2$)
	m.PluginSystemLog.SendLine(line3$)
	m.ptpCurrentState$ = newState$
	m.ptpStateChangedAt = changedAt
	return true
End Function



' Starts a 60-second one-shot timer. The handler in HandleTimerEventPlugin logs the
' current PTP status then restarts it, giving a periodic record of PTP state between
' state-change events — useful for tracking convergence time after boot or disruption.
Function StartPtpPollTimer()
	newTimeout = m.sTime.GetLocalDateTime()
	newTimeout.AddSeconds(60)
	m.PtpPollTimer = CreateObject("roTimer")
	m.PtpPollTimer.SetPort(m.msgPort)
	m.PtpPollTimer.SetDateTime(newTimeout)
	m.PtpPollTimer.Start()
End Function



' Prints the CSV header row to the console (no file is written).
' Called after PluginConfigDevice() so Player_is_Master is already set.
Sub InitSyncTimingLog()
	if m.Player_is_Master = true then
		m.logFileName$ = "master"
	else
		m.logFileName$ = "slave"
	end if
	header$ = "PlayerRole,Loop,SyncId,SyncEventTime,SyncIsoTimestamp,VideoPlayingTime"
	m.syncLoggingActive = true
	print ""
	print "SyncTimingLog: initialized - " + m.logFileName$
	print "SyncTimingLog: " + header$
	print "SyncTimingLog: will capture " + stri(m.syncMaxLoops) + " loops then stop"
	print ""
End Sub



' Prints one row to the console for a single sync→play cycle (no file is written).
' Called from HandlePluginVideoEvent when event 3 (playing) fires.
Sub WriteSyncTimingEntry(syncId as integer, syncEventTime$ as string, isoTimestamp$ as string, videoPlayingTime$ as string)
	if m.Player_is_Master = true then
		playerRole$ = "master"
	else
		playerRole$ = "slave"
	end if
	line$ = playerRole$ + "," + stri(m.syncLoopCount + 1) + "," + stri(syncId) + "," + syncEventTime$ + "," + isoTimestamp$ + "," + videoPlayingTime$
	print "SyncTimingLog: "; line$
End Sub



Function SetupSyncManager()

    SyncManUserdata = {}
    SyncManUserdata.name = "rlb-sync-manager"	

	m.aa = {}
	m.aa.Domain = "0"
	m.PluginSyncManager = CreateObject("roSyncManager", m.aa)
	if m.Player_is_Master = true then
		setOK = m.PluginSyncManager.SetAsLeader(true)
		print ""
		print "SetAsLeader returned: "; setOK
		print ""
	end if	
	m.PluginSyncManager.SetPort(m.msgPort)
	m.PluginSyncManager.SetUserData(SyncManUserdata)
End function



' SetLoopMode(1) for a single-item playlist, SetLoopMode(0) for more than one item.
Sub ApplyLoopMode()
	if m.seamlessLooping = 1 then
		loopModeApplied% = 1
	else
		loopModeApplied% = 0
	end if
	m.PluginvideoPlayer.SetLoopMode(loopModeApplied%)
	print ""
	print "ApplyLoopMode - SetLoopMode applied: "; loopModeApplied%
	print ""
End Sub



Function BuildPluginPlayers()

    VidUserdata = {}
    VidUserdata.name = "rlb-sync-video-player"
	m.PluginvideoPlayer = CreateObject("roVideoPlayer")
	m.PluginvideoPlayer.SetUserData(VidUserdata)
	m.PluginImagePlayer = CreateObject("roImagePlayer")
	m.rect1 = CreateObject("roRectangle", 0, 0, m.vm.GetResX(), m.vm.GetResY())
	m.PluginvideoPlayer.SetRectangle(m.rect1)
	m.PluginImagePlayer.SetDefaultTransition(15)
	m.PluginImagePlayer.SetTransitionDuration(3000)
	m.PluginvideoPlayer.SetPort(m.msgPort)
	m.PluginvideoPlayer.SetAudioOutput(4)
	m.PluginvideoPlayer.SetVolume(100)
	m.ApplyLoopMode()

	print ""
	print "BuildPluginPlayers - PluginVideoPlayer and PluginImagePlayer created and configured"
	print "PluginVideoPlayer type(): "; type(m.PluginvideoPlayer)
	print "m.seamlessLooping: "; m.seamlessLooping
	print ""
End Function