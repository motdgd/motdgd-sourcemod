#pragma semicolon 1

#define MOTD_TITLE "MOTDGD AD"
#define PLUGIN_VERSION "1.6.3"
#define UPDATE_URL "http://motdgd.com/motdgd_adverts_version.txt"

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <updater>

new Handle:cvForced = INVALID_HANDLE;
new Handle:cvImmunity = INVALID_HANDLE;
new Handle:cvMotdUrl = INVALID_HANDLE;
new Handle:cvReviewMode = INVALID_HANDLE;
new Handle:cvReviewTime = INVALID_HANDLE;
new bool:isCSGO = false;
new bool:isCSS = false;
new bool:isDOD = false;
new bool:isL4D = false;
new bool:isL4D2 = false;
new bool:isTF = false;
new bool:isUnknown = false;
new iServerPort = -1;
new iVGUIForcing[MAXPLAYERS + 1] = { 0, ... };
new iVGUICaught[MAXPLAYERS + 1] = { 0, ... };
new timePlayerReview[MAXPLAYERS + 1] = { 0, ... };

new String:sServerIPPort[32];

public Plugin:myinfo = 
{
	name = "MOTDgd Ads",
	author = "MOTDgd",
	description = "Intercepts the MOTD and points it to an MOTDgd advertisement",
	version = PLUGIN_VERSION,
	url = "http://motdgd.com"
};

public OnPluginStart()
{
	// Updater plugin support
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	
	// Initialize our ConVars
	cvMotdUrl = CreateConVar("sm_motdgd_url", "", "The MOTD URL found on Your Portal Dashboard at motdgd.com");
	cvForced = CreateConVar("sm_motdgd_forced", "6", "Whether eligible players are forced to see MOTDgd for up to X seconds, 0 is disabled, default is 6 seconds");
	cvImmunity = CreateConVar("sm_motdgd_immunity", "1", "Whether ADMIN_RESERVATION players are immune to MOTDgd advertisements");
	cvReviewMode = CreateConVar("sm_motdgd_review_mode", "1", "Whether eligible players are shown MOTDgd after [review_minutes] have passed, 0 is on death, 1 is on round start (default)");
	cvReviewTime = CreateConVar("sm_motdgd_review_minutes", "30", "Whether eligible players are shown MOTDgd every X minutes during the game, 0 is disabled, minimum 20 minutes");
	AutoExecConfig(true);
	
	CreateConVar("sm_motdgd_version", PLUGIN_VERSION, "MOTDgd Plugin Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	// Initialize our global variables
	new Handle:h_hostIP = FindConVar("hostip");
	new Handle:h_hostPort = FindConVar("hostport");
	if(h_hostIP == INVALID_HANDLE || h_hostPort == INVALID_HANDLE)
	{
		SetFailState("Failed to determine server ip and port.");
	}
	
	iServerPort = GetConVarInt(h_hostPort);
	
	new iServerIP = GetConVarInt(h_hostIP);
	Format(sServerIPPort, sizeof(sServerIPPort), "%d.%d.%d.%d&pt=%d", iServerIP >>> 24 & 255, iServerIP >>> 16 & 255, iServerIP >>> 8 & 255, iServerIP & 255, iServerPort);
	
	new String:gameDir[64];
	GetGameFolderName(gameDir, sizeof(gameDir));
	if (strcmp(gameDir, "csgo") == 0)
	{
		isCSGO = true;
	}
	else if (strcmp(gameDir, "cstrike") == 0)
	{
		isCSS = true;
	}
	else if (strcmp(gameDir, "dod") == 0)
	{
		isDOD = true;
	}
	else if (strcmp(gameDir, "l4d") == 0)
	{
		isL4D = true;
	}
	else if (strcmp(gameDir, "l4d2") == 0)
	{
		isL4D2 = true;
	}
	else if (strcmp(gameDir, "tf") == 0)
	{
		isTF = true;
	}
	else
	{
		isUnknown = true;
	}
	
	if (isCSGO || isCSS || isDOD || isL4D || isL4D2 || isTF || isUnknown)
	{
		// Intercept the MOTD window and show our ad instead
		new UserMsg:umVGUIMenu = GetUserMessageId("VGUIMenu");
		if (umVGUIMenu == INVALID_MESSAGE_ID)
		{
			SetFailState("This game doesn't support VGUI menus.");
		}
		HookUserMessage(umVGUIMenu, Hook_VGUIMenu, true);
		AddCommandListener(ClosedHTMLPage, "closed_htmlpage");
	}
	
	if (isL4D || isL4D2)
	{
		// Show MOTD after the campaign selection (if any)
		HookEvent("player_transitioned", Event_PlayerTransitioned);
	}
	
	if (GetConVarInt(cvReviewTime) > 0)
	{
		switch (GetConVarInt(cvReviewMode))
		{
			case 0:
			{
				HookEvent("player_death", Event_PlayerDeath);
				CreateTimer(60.0, ReviewTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
			
			case 1:
			{
				if (isTF)
				{
					HookEvent("teamplay_round_start", Event_RoundStart);
				}
				else
				{
					HookEvent("round_start", Event_RoundStart);
				}
				
				CreateTimer(60.0, ReviewTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}

public OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public OnClientConnected(client)
{
	ResetClientVars(client);
}

public OnClientDisconnect(client)
{
	ResetClientVars(client);
}

ResetClientVars(client)
{
	iVGUICaught[client] = 0;
	iVGUIForcing[client] = 0;
	
	if(GetConVarInt(cvReviewTime) > 20)
	{
		timePlayerReview[client] = GetConVarInt(cvReviewTime);
	}
	else if(GetConVarInt(cvReviewTime) > 0)
	{
		timePlayerReview[client] = 20;
	}
	else
	{
		timePlayerReview[client] = -1;
	}
}

public CheckReview(client)
{
	if(GetConVarInt(cvReviewTime) > 0)
	{
		if(IsPlayerValid(client) && !IsFakeClient(client))
		{
			if(timePlayerReview[client] == 0)
			{
				// If the player has ADMIN_RESERVATION and immunity cvar is set to 1 then don't show them MOTDgd
				if (!CanViewMOTDgd(client) && GetConVarInt(cvImmunity) == 1)
				{
					return;
				}
				
				if (GetConVarInt(cvReviewTime) > 20)
				{
					timePlayerReview[client] = GetConVarInt(cvReviewTime);
				}
				else
				{
					timePlayerReview[client] = 20;
				}
				
				CreateTimer(3.0, NewMOTD, GetClientUserId(client));
			}
		}
	}
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victimId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(victimId);
	
	CheckReview(client);
	
	return Plugin_Continue;
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	for (new i = 1; i < (MAXPLAYERS + 1); i++)
	{
		if(IsPlayerValid(i) && !IsFakeClient(i))
		{
			CheckReview(i);
		}
	}
	
	return Plugin_Continue;
}

public Action:Event_PlayerTransitioned(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (IsPlayerValid(client) && !IsFakeClient(client))
	{
		iVGUICaught[client] = 1;
		
		// If the player has ADMIN_RESERVATION and immunity cvar is set to 1 then don't show them MOTDgd
		if (!CanViewMOTDgd(client) && GetConVarInt(cvImmunity) == 1)
		{
			return Plugin_Continue;
		}
		
		CreateTimer(0.1, NewMOTD, GetClientUserId(client));
	}
	
	return Plugin_Continue;
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("GetUserMessageType");
}

public Action:Hook_VGUIMenu(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	new client = players[0];
	if(playersNum > 1 || !IsPlayerValid(client))
	{
		return Plugin_Continue;
	}
	
	// Skip if the player's MOTD has been intercepted
	if (iVGUICaught[client] > 0)
	{
		return Plugin_Continue;
	}
	
	new String:sName[64];
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
	{
		PbReadString(bf, sName, "name", sizeof(sName));
	}
	else
	{
		BfReadString(bf, sName, sizeof(sName));
	}

	if (strcmp(sName, "info") != 0)
	{
		return Plugin_Continue;
	}
	
	// Don't repeat the interception more than once
	iVGUICaught[client] = 1;
	
	// If the player has ADMIN_RESERVATION and immunity cvar is set to 1 then don't show them MOTDgd
	if (!CanViewMOTDgd(client) && GetConVarInt(cvImmunity) == 1)
	{
		return Plugin_Continue;
	}
	
	// Display MOTDgd
	CreateTimer(0.1, NewMOTD, GetClientUserId(client));

	return Plugin_Handled;
}

public Action:ClosedHTMLPage(client, const String:command[], argc)
{
	if(IsPlayerValid(client))
	{
		if((GetConVarInt(cvForced) == 0 && !IsValidTeam(client)) || (GetConVarInt(cvForced) >= 1 && !IsValidTeam(client) && iVGUIForcing[client] == 0))
		{
			// To ensure player can choose a team after closing the MOTD
			FakeClientCommand(client, "joingame");
		}
		else if(GetConVarInt(cvForced) >= 1 && !IsValidTeam(client) && iVGUIForcing[client] == 1)
		{
			// Display MOTDgd
			CreateTimer(0.1, ReOpenMOTD, GetClientUserId(client));
		}
	}
	
	return Plugin_Continue;
}

public Action:NewMOTD(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(IsPlayerValid(client))
	{
		new String:sURL[192];
		GetConVarString(cvMotdUrl, sURL, sizeof(sURL));
		SendMOTD(client, MOTD_TITLE, sURL);
		if (GetConVarInt(cvForced) >= 1 && iVGUIForcing[client] == 0)
		{
			// If the player must be forced to see MOTDgd for a short duration
			iVGUIForcing[client] = 1;
			CreateTimer(GetConVarFloat(cvForced), UnlockMOTD, GetClientUserId(client));
		}
	}
}

public Action:ReOpenMOTD(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(IsPlayerValid(client))
	{
		SendVoidMOTD(client, MOTD_TITLE, "javascript:void(0);");
	}
}

public Action:ReviewTimer(Handle:timer)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsPlayerValid(i) && !IsFakeClient(i))
		{
			if(timePlayerReview[i] > 0)
			{
				timePlayerReview[i]--;
			}
		}
	}
}

public Action:UnlockMOTD(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(IsPlayerValid(client))
	{
		iVGUIForcing[client] = 0;
	}
}

stock SendMOTD(client, const String:title[], const String:url[], bool:show=true)
{
	if(IsPlayerValid(client))
	{
		new Handle:kv = CreateKeyValues("data");
		if (!isL4D && !isL4D2)
			KvSetNum(kv, "cmd", 5);
		else
			KvSetString(kv, "cmd", "closed_htmlpage");
		
		new String:clientAuth[64];
		GetClientAuthString(client, clientAuth, sizeof(clientAuth));
		
		new String:sURL[128];
		Format(sURL, sizeof(sURL), "%s&ip=%s&v=%s&fv=%i&st=%s", url, sServerIPPort, PLUGIN_VERSION, GetConVarInt(cvForced), clientAuth);
		
		KvSetString(kv, "msg", sURL);
		KvSetString(kv, "title", title);
		KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
		
		ShowVGUIPanel(client, "info", kv, show);
		CloseHandle(kv);
	}
}

stock SendVoidMOTD(client, const String:title[], const String:url[], bool:show=true)
{
	if(IsPlayerValid(client))
	{
		new Handle:kv = CreateKeyValues("data");
		if (!isL4D && !isL4D2)
			KvSetNum(kv, "cmd", 5);
		else
			KvSetString(kv, "cmd", "closed_htmlpage");
		
		new String:sURL[128];
		Format(sURL, sizeof(sURL), "%s", url);
		
		KvSetString(kv, "msg", sURL);
		KvSetString(kv, "title", title);
		KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
		
		ShowVGUIPanel(client, "info", kv, show);
		CloseHandle(kv);
	}
}

bool:IsValidTeam(client)
{
	return (GetClientTeam(client) != 0);
}

stock bool:CanViewMOTDgd(client)
{
	if(IsPlayerValid(client) && !IsFakeClient(client))
	{
		new AdminId:aId = GetUserAdmin( client );
		if(aId == INVALID_ADMIN_ID)
		{
			return true;
		}
		if(GetAdminFlag(aId, Admin_Reservation))
		{
			return false;
		}
	}
	return true;
}
stock bool:IsPlayerValid(client)
{
	if(client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client))
	{
		return true;
	}
	return false;
}

