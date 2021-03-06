local CATEGORY_NAME = "Voting"

---------------
--Public vote--
---------------
if SERVER then ulx.convar( "voteEcho", "0", _, ULib.ACCESS_SUPERADMIN ) end -- Echo votes?

-- First, our helper function to make voting so much easier!
local voteInProgress
function ulx.doVote( title, options, callback, timeout, filter, noecho, ... )
	timeout = timeout or 20
	if voteInProgress then
		Msg( "Error! ULX tried to start a vote when another vote was in progress!\n" )
		return
	end

	if not options[ 1 ] or not options[ 2 ] then
		Msg( "Error! ULX tried to start a vote without at least two options!\n" )
		return
	end

	local voters = 0
	local rp = RecipientFilter()
	if not filter then
		rp:AddAllPlayers()
		voters = #player.GetAll()
	else
		for _, ply in ipairs( filter ) do
			rp:AddPlayer( ply )
			voters = voters + 1
		end
	end

	umsg.Start( "ulx_vote", rp )
		umsg.String( title )
		umsg.Short( timeout )
		ULib.umsgSend( options )
	umsg.End()

	voteInProgress = { callback=callback, options=options, title=title, results={}, voters=voters, votes=0, noecho=noecho, args={...} }

	timer.Create( "ULXVoteTimeout", timeout, 1, ulx.voteDone )
end

function ulx.voteCallback( ply, command, argv )
	if not voteInProgress then
		ULib.tsayError( ply, "There is not a vote in progress" )
		return
	end

	if not argv[ 1 ] or not tonumber( argv[ 1 ] ) or not voteInProgress.options[ tonumber( argv[ 1 ] ) ] then
		ULib.tsayError( ply, "Invalid or out of range vote." )
		return
	end

	if ply.ulxVoted then
		ULib.tsayError( ply, "You have already voted!" )
		return
	end

	local echo = util.tobool( GetConVarNumber( "ulx_voteEcho" ) )
	local id = tonumber( argv[ 1 ] )
	voteInProgress.results[ id ] = voteInProgress.results[ id ] or 0
	voteInProgress.results[ id ] = voteInProgress.results[ id ] + 1

	voteInProgress.votes = voteInProgress.votes + 1

	ply.ulxVoted = true -- Tag them as having voted

	local str = ply:Nick() .. " voted for: " .. voteInProgress.options[ id ]
	if echo and not voteInProgress.noecho then
		ULib.tsay( _, str ) -- TODO, color?
	end
	ulx.logString( str )
	if game.IsDedicated() then Msg( str .. "\n" ) end

	if voteInProgress.votes >= voteInProgress.voters then
		timer.Destroy( "ULXVoteTimeout" )
		ulx.voteDone()
	end
end
if SERVER then concommand.Add( "ulx_vote", ulx.voteCallback ) end

function ulx.voteDone()
	local players = player.GetAll()
	for _, ply in ipairs( players ) do -- Clear voting tags
		ply.ulxVoted = nil
	end

	local vip = voteInProgress
	voteInProgress = nil
	ULib.pcallError( vip.callback, vip, unpack( vip.args, 1, 10 ) ) -- Unpack is explicit in length to avoid odd LuaJIT quirk.
end
-- End our helper functions





local function voteDone( t )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local str
	if not winner then
		str = "Vote results: No option won because no one voted!"
	else
		str = "Vote results: Option '" .. t.options[ winner ] .. "' won. (" .. winnernum .. "/" .. t.voters .. ")"
	end
	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	Msg( str .. "\n" )
end

function ulx.vote( calling_ply, title, ... )
	if voteInProgress then
		ULib.tsayError( calling_ply, "There is already a vote in progress. Please wait for the current one to end.", true )
		return
	end

	ulx.doVote( title, { ... }, voteDone )
	ulx.fancyLogAdmin( calling_ply, "#A started a vote (#s)", title )
end
local vote = ulx.command( CATEGORY_NAME, "ulx vote", ulx.vote, "!vote" )
vote:addParam{ type=ULib.cmds.StringArg, hint="title" }
vote:addParam{ type=ULib.cmds.StringArg, hint="options", ULib.cmds.takeRestOfLine, repeat_min=2, repeat_max=10 }
vote:defaultAccess( ULib.ACCESS_ADMIN )
vote:help( "Starts a public vote." )


local function voteMapDone2( t, changeTo, ply )
	local shouldChange = false

	if t.results[ 1 ] and t.results[ 1 ] > 0 then
		ulx.logServAct( ply, "#A approved the votemap" )
		shouldChange = true
	else
		ulx.logServAct( ply, "#A denied the votemap" )
	end

	if shouldChange then
		ULib.consoleCommand( "changelevel " .. changeTo .. "\n" )
	end
end

local function voteMapDone( t, argv, ply )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local ratioNeeded = GetConVarNumber( "ulx_votemap2Successratio" )
	local minVotes = GetConVarNumber( "ulx_votemap2Minvotes" )
	local str
	local changeTo
	if (#argv < 2 and winner ~= 1) or not winner or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
		str = "Vote results: Vote was unsuccessful."
	else
		str = "Vote results: Option '" .. t.options[ winner ] .. "' won, changemap pending approval. (" .. winnernum .. "/" .. t.voters .. ")"

		-- Figure out the map to change to.
		if #argv > 1 then
			changeTo = t.options[ winner ]
		else
			changeTo = argv[ 1 ]
		end

		ulx.doVote( "Accept result and changemap to " .. changeTo .. "?", { "Yes", "No" }, voteMapDone2, 30000, { ply }, true, changeTo, ply )
	end
	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	if game.IsDedicated() then Msg( str .. "\n" ) end
end

function ulx.votemap2( calling_ply, ... )
	local argv = { ... }

	if voteInProgress then
		ULib.tsayError( calling_ply, "There is already a vote in progress. Please wait for the current one to end.", true )
		return
	end

	for i=2, #argv do
	    if ULib.findInTable( argv, argv[ i ], 1, i-1 ) then
	        ULib.tsayError( calling_ply, "Map " .. argv[ i ] .. " was listed twice. Please try again" )
	        return
	    end
	end

	if #argv > 1 then
		ulx.doVote( "Change map to..", argv, voteMapDone, _, _, _, argv, calling_ply )
		ulx.fancyLogAdmin( calling_ply, "#A started a votemap with options" .. string.rep( " #s", #argv ), ... )
	else
		ulx.doVote( "Change map to " .. argv[ 1 ] .. "?", { "Yes", "No" }, voteMapDone, _, _, _, argv, calling_ply )
		ulx.fancyLogAdmin( calling_ply, "#A started a votemap for #s", argv[ 1 ] )
	end
end
local votemap2 = ulx.command( CATEGORY_NAME, "ulx votemap2", ulx.votemap2, "!votemap2" )
votemap2:addParam{ type=ULib.cmds.StringArg, completes=ulx.maps, hint="map", error="invalid map \"%s\" specified", ULib.cmds.restrictToCompletes, ULib.cmds.takeRestOfLine, repeat_min=1, repeat_max=10 }
votemap2:defaultAccess( ULib.ACCESS_ADMIN )
votemap2:help( "Starts a public map vote." )
if SERVER then ulx.convar( "votemap2Successratio", "0.5", _, ULib.ACCESS_ADMIN ) end -- The ratio needed for a votemap2 to succeed
if SERVER then ulx.convar( "votemap2Minvotes", "3", _, ULib.ACCESS_ADMIN ) end -- Minimum votes needed for votemap2



local function voteKickDone2( t, target, time, ply, reason )
	local shouldKick = false

	if t.results[ 1 ] and t.results[ 1 ] > 0 then
		ulx.logUserAct( ply, target, "#A approved the votekick against #T (" .. (reason or "") .. ")" )
		shouldKick = true
	else
		ulx.logUserAct( ply, target, "#A denied the votekick against #T" )
	end

	if shouldKick then
		if reason and reason ~= "" then
			ULib.kick( target, "Vote kick successful. (" .. reason .. ")" )
		else
			ULib.kick( target, "Vote kick successful." )
		end
	end
end

local function voteKickDone( t, target, time, ply, reason )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local ratioNeeded = GetConVarNumber( "ulx_votekickSuccessratio" )
	local minVotes = GetConVarNumber( "ulx_votekickMinvotes" )
	local str
	if winner ~= 1 or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
		str = "Vote results: User will not be kicked. (" .. (results[ 1 ] or "0") .. "/" .. t.voters .. ")"
	else
		str = "Vote results: User will now be kicked, pending approval. (" .. winnernum .. "/" .. t.voters .. ")"
		ulx.doVote( "Accept result and kick " .. target:Nick() .. "?", { "Yes", "No" }, voteKickDone2, 30000, { ply }, true, target, time, ply, reason )
	end

	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	if game.IsDedicated() then Msg( str .. "\n" ) end
end

function ulx.votekick( calling_ply, target_ply, reason )
	if voteInProgress then
		ULib.tsayError( calling_ply, "There is already a vote in progress. Please wait for the current one to end.", true )
		return
	end

	local msg = "Kick " .. target_ply:Nick() .. "?"
	if reason and reason ~= "" then
		msg = msg .. " (" .. reason .. ")"
	end

	ulx.doVote( msg, { "Yes", "No" }, voteKickDone, _, _, _, target_ply, time, calling_ply, reason )
	ulx.fancyLogAdmin( calling_ply, "#A started a votekick against #T", target_ply )
end
local votekick = ulx.command( CATEGORY_NAME, "ulx votekick", ulx.votekick, "!votekick" )
votekick:addParam{ type=ULib.cmds.PlayerArg }
votekick:addParam{ type=ULib.cmds.StringArg, hint="reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.common_kick_reasons }
votekick:defaultAccess( ULib.ACCESS_ADMIN )
votekick:help( "Starts a public kick vote against target." )
if SERVER then ulx.convar( "votekickSuccessratio", "0.6", _, ULib.ACCESS_ADMIN ) end -- The ratio needed for a votekick to succeed
if SERVER then ulx.convar( "votekickMinvotes", "2", _, ULib.ACCESS_ADMIN ) end -- Minimum votes needed for votekick



local function voteBanDone2( t, target, time, ply, reason )
	local shouldBan = false

	if t.results[ 1 ] and t.results[ 1 ] > 0 then
		ulx.logUserAct( ply, target, "#A approved the voteban against #T (" .. time .. " minutes) (" .. (reason or "") .. ")" )
		shouldBan = true
	else
		ulx.logUserAct( ply, target, "#A denied the voteban against #T" )
	end

	if shouldBan then
		if reason and reason ~= "" then
			ULib.kick( target, "Vote ban successful. (" .. reason .. ")" )
		else
			ULib.kick( target, "Vote ban successful." )
		end
		ULib.ban( target, time, reason, ply )
	end
end

local function voteBanDone( t, target, time, ply, reason )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local ratioNeeded = GetConVarNumber( "ulx_votebanSuccessratio" )
	local minVotes = GetConVarNumber( "ulx_votebanMinvotes" )
	local str
	if winner ~= 1 or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
		str = "Vote results: User will not be banned. (" .. (results[ 1 ] or "0") .. "/" .. t.voters .. ")"
	else
		str = "Vote results: User will now be banned for " .. time .. " minutes, pending approval. (" .. winnernum .. "/" .. t.voters .. ")"
		ulx.doVote( "Accept result and ban " .. target:Nick() .. "?", { "Yes", "No" }, voteBanDone2, 30000, { ply }, true, target, time, ply, reason )
	end

	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	Msg( str .. "\n" )
end

function ulx.voteban( calling_ply, target_ply, minutes, reason )
	if voteInProgress then
		ULib.tsayError( calling_ply, "There is already a vote in progress. Please wait for the current one to end.", true )
		return
	end

	local msg = "Ban " .. target_ply:Nick() .. " for " .. minutes .. " minutes?"
	if reason and reason ~= "" then
		msg = msg .. " (" .. reason .. ")"
	end

	ulx.doVote( msg, { "Yes", "No" }, voteBanDone, _, _, _, target_ply, minutes, calling_ply, reason )
	if reason and reason ~= "" then
		ulx.fancyLogAdmin( calling_ply, "#A started a voteban of #i minute(s) against #T (#s)", minutes, target_ply, reason )
	else
		ulx.fancyLogAdmin( calling_ply, "#A started a voteban of #i minute(s) against #T", minutes, target_ply )
	end
end
local voteban = ulx.command( CATEGORY_NAME, "ulx voteban", ulx.voteban, "!voteban" )
voteban:addParam{ type=ULib.cmds.PlayerArg }
voteban:addParam{ type=ULib.cmds.NumArg, min=0, default=1440, hint="minutes", ULib.cmds.allowTimeString, ULib.cmds.optional }
voteban:addParam{ type=ULib.cmds.StringArg, hint="reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.common_kick_reasons }
voteban:defaultAccess( ULib.ACCESS_ADMIN )
voteban:help( "Starts a public ban vote against target." )
if SERVER then ulx.convar( "votebanSuccessratio", "0.7", _, ULib.ACCESS_ADMIN ) end -- The ratio needed for a voteban to succeed
if SERVER then ulx.convar( "votebanMinvotes", "3", _, ULib.ACCESS_ADMIN ) end -- Minimum votes needed for voteban

-- Our regular votemap command
local votemap = ulx.command( CATEGORY_NAME, "ulx votemap", ulx.votemap, "!votemap" )
votemap:addParam{ type=ULib.cmds.StringArg, completes=ulx.votemaps, hint="map", ULib.cmds.takeRestOfLine, ULib.cmds.optional }
votemap:defaultAccess( ULib.ACCESS_ALL )
votemap:help( "Vote for a map, no args lists available maps." )

-- Our veto command
local veto = ulx.command( CATEGORY_NAME, "ulx veto", ulx.votemapVeto, "!veto" )
veto:defaultAccess( ULib.ACCESS_ADMIN )
veto:help( "Veto a successful votemap" )
