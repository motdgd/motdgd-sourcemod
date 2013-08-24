#pragma semicolon 1

//////////////////////////////
//		DEFINITIONS			//
//////////////////////////////

#define PLUGIN_NAME "MOTDgd Adverts"
#define PLUGIN_AUTHOR "Zephyrus (Modified by Ixel)"
#define PLUGIN_DESCRIPTION "Intercepts the MOTD and points it to an MOTDgd advertisement"
#define PLUGIN_VERSION "2.0.2"
#define PLUGIN_URL "http://motdgd.com"

#define MOTDGD_BACKEND_URL "http://motdgd.com/ads/backend.php"
#define MOTDGD_UPDATE_URL "http://motdgd.com/motdgd_adverts_2_version.txt"
#define MOTDGD_MOTD_TITLE "SPONSORED AD"

//////////////////////////////
//			INCLUDES		//
//////////////////////////////

#include <sourcemod>
#include <sdktools>

#include <zephstocks>
#include <easyhttp>
#include <easyjson>
#include <easyupdate>

//////////////////////////////
//			ENUMS			//
//////////////////////////////

enum EClientState
{
	State_Done,
	State_Waiting,
	State_Requesting,
	State_Viewing,
}

enum ETrigger
{
	Undefined,
	Connection,
	Death,
	RoundEnd,
	Transition,
}

//////////////////////////////////
//		GLOBAL VARIABLES		//
//////////////////////////////////

new g_cvarMotdUrl = -1;
new g_cvarImmunityFlag = -1;
new g_cvarImmunityMode = -1;
new g_cvarTimeout = -1;
new g_cvarForcedDuration = -1;
new g_cvarMaximumDuration = -1;
new g_cvarCooldown = -1;
new g_cvarConnectionAds = -1;
new g_cvarDeathAds = -1;
new g_cvarRoundAds = -1;
new g_cvarTransitionAds = -1;
new g_cvarShowOriginal = -1;

new String:g_szOriginalMOTD[MAXPLAYERS+1][256];
new String:g_szOriginalMOTDTitle[MAXPLAYERS+1][256];
new String:g_szServerIP[16];

new g_iServerPort;
new g_iClientDuration[MAXPLAYERS+1];
new g_iClientAdStart[MAXPLAYERS+1];
new g_iOriginalMOTDType[MAXPLAYERS+1];

new bool:g_bOriginalMOTD[MAXPLAYERS+1];

new EClientState:g_eClientState[MAXPLAYERS+1];
new ETrigger:g_eClientTrigger[MAXPLAYERS+1];

//////////////////////////////////
//		PLUGIN DEFINITION		//
//////////////////////////////////

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

//////////////////////////////
//		PLUGIN FORWARDS		//
//////////////////////////////

public OnPluginStart()
{
	// Set up booleans for a few games that require customized actions
	IdentifyGame();

	// Initialize our ConVars
	g_cvarMotdUrl = RegisterConVar("sm_motdgd_url", "", "The MOTD URL found on Your Portal Dashboard at motdgd.com", TYPE_STRING);
	g_cvarImmunityFlag = RegisterConVar("sm_motdgd_immunity_flag", "", "Players with this SourceMod flag set will be given ad viewing immunity. Use 'sm_motdgd_immunity_mode' setting to set the level of immunity.", TYPE_FLAG);
	g_cvarImmunityMode = RegisterConVar("sm_motdgd_immunity_mode", "0", "0-Disables ads completely for immune players, 1-Still shows immune players the ads but won't force them to watch it.", TYPE_INT);
	g_cvarForcedDuration = RegisterConVar("sm_motdgd_force_duration", "1", "[1-Enable, 0-Disable] If enabled, the minimum viewing duration of an ad will be set to the actual length of the ad (but limited by the 'sm_motdgd_max_duration' variable).", TYPE_INT, INVALID_FUNCTION, 0, true, 0.0, true, 1.0);
	g_cvarMaximumDuration = RegisterConVar("sm_motdgd_max_duration", "6", "The maximum number of seconds a player will be forced to watch an ad. Setting this to 0 disables maximum duration.", TYPE_INT);
	g_cvarTimeout = RegisterConVar("sm_motdgd_timeout", "6", "The maximum number of seconds to wait before letting the player close his motd if an ad hasn't loaded.", TYPE_INT);
	g_cvarCooldown = RegisterConVar("sm_motdgd_cooldown", "15", "How frequently (in minutes) that ads can shown again (AKA: Cooldown period)", TYPE_INT);
	g_cvarConnectionAds = RegisterConVar("sm_motdgd_ads_on_connection", "1", "[1-Enable, 0-Disable] Enabling this will show ads to players once they connect to the server.", TYPE_INT, INVALID_FUNCTION, 0, true, 0.0, true, 1.0);
	g_cvarDeathAds = RegisterConVar("sm_motdgd_ads_on_death", "0", "[1-Enable, 0-Disable] Enabling this will show ads to dead players.", TYPE_INT, INVALID_FUNCTION, 0, true, 0.0, true, 1.0);
	g_cvarShowOriginal = RegisterConVar("sm_motdgd_show_original_motd", "0", "[1-Enable, 0-Disable] Show the original MOTD once the ad has finished. Not recommended to enable unless you need to.", TYPE_INT);

	if(g_bTF || g_bDOD)
		g_cvarRoundAds = RegisterConVar("sm_motdgd_ads_on_round_end", "0", "1-Show ads to players on round start, 2-Show ads players at round end.", TYPE_INT, INVALID_FUNCTION, 0, true, 0.0, true, 2.0);
	else
		g_cvarRoundAds = RegisterConVar("sm_motdgd_ads_on_round_end", "1", "1-Show ads to players on round start, 2-Show ads players at round end.", TYPE_INT, INVALID_FUNCTION, 0, true, 0.0, true, 2.0);
	g_cvarTransitionAds = RegisterConVar("sm_motdgd_ads_on_transition", "0", "[1-Enable, 0-Disable] Enabling this will show ads in L4D between map stages.", TYPE_INT, INVALID_FUNCTION, 0, true, 0.0, true, 1.0);

	AutoExecConfig();

	RegisterConVar("sm_motdgd_version", PLUGIN_VERSION, "MOTDgd Plugin Version", TYPE_STRING, INVALID_FUNCTION, FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// Check if any of the required extensions is loaded
	EasyHTTPCheckExtensions();
	if(!g_bCURL && !g_bSockets && ! g_bSteamTools)
		SetFailState("For this plugin to run you need ONE of these extensions installed:\n\
			cURL - http://forums.alliedmods.net/showthread.php?t=152216\n\
			SteamTools - http://forums.alliedmods.net/showthread.php?t=129763\n\
			Socket - http://forums.alliedmods.net/showthread.php?t=67640");

	// Initialize our global variables
	new Handle:m_hHostIP = FindConVar("hostip");
	new Handle:m_hHostPort = FindConVar("hostport");
	if(m_hHostIP == INVALID_HANDLE || m_hHostPort == INVALID_HANDLE)
		SetFailState("Failed to determine server ip and port.");

	g_iServerPort = GetConVarInt(m_hHostPort);

	new m_iServerIP = GetConVarInt(m_hHostIP);
	Format(STRING(g_szServerIP), "%d.%d.%d.%d", m_iServerIP >>> 24 & 255, m_iServerIP >>> 16 & 255, m_iServerIP >>> 8 & 255, m_iServerIP & 255);

	// Intercept the MOTD window and show our ad instead
	new UserMsg:m_eVGUIMenu = GetUserMessageId("VGUIMenu");
	if (m_eVGUIMenu == INVALID_MESSAGE_ID)
		SetFailState("This game doesn't support VGUI menus.");
	HookUserMessage(m_eVGUIMenu, Hook_VGUIMenu, true);
	AddCommandListener(Command_ClosedHTMLPage, "closed_htmlpage");

	// Hook the events we may need
	if(g_bTF)
	{
		HookEvent("teamplay_round_start", Event_RoundStart);
		HookEvent("teamplay_win_panel", Event_RoundEnd);
		HookEvent("arena_win_panel", Event_RoundEnd);
	}
	else if(g_bL4D || g_bL4D2)
		HookEvent("player_transitioned", Event_PlayerTransitioned);
	else if(g_bCSS || g_bCSGO)
	{
		HookEvent("round_start", Event_RoundStart);
		HookEvent("round_end", Event_RoundEnd);
	}
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_PlayerTeam);

	// Check the plugin for updates
	EasyUpdate(MOTDGD_UPDATE_URL);
}

public OnConfigsExecuted()
{
	// Check if the server owner has set the motd url
	if(g_eCvars[g_cvarMotdUrl][sCache][0] == 0)
		SetFailState("Your motd URL is not set. Please visit http://www.motdgd.com/ for more info.");
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Mark GetUserMessageType as an optional native
	MarkNativeAsOptional("GetUserMessageType");

	// Mark Socket natives as optional
	MarkNativeAsOptional("SocketIsConnected");
	MarkNativeAsOptional("SocketCreate");
	MarkNativeAsOptional("SocketBind");
	MarkNativeAsOptional("SocketConnect");
	MarkNativeAsOptional("SocketDisconnect");
	MarkNativeAsOptional("SocketListen");
	MarkNativeAsOptional("SocketSend");
	MarkNativeAsOptional("SocketSendTo");
	MarkNativeAsOptional("SocketSetOption");
	MarkNativeAsOptional("SocketSetReceiveCallback");
	MarkNativeAsOptional("SocketSetSendqueueEmptyCallback");
	MarkNativeAsOptional("SocketSetDisconnectCallback");
	MarkNativeAsOptional("SocketSetErrorCallback");
	MarkNativeAsOptional("SocketSetArg");
	MarkNativeAsOptional("SocketGetHostName");

	// Mark SteamTools natives as optional
	MarkNativeAsOptional("Steam_IsVACEnabled");
	MarkNativeAsOptional("Steam_GetPublicIP");
	MarkNativeAsOptional("Steam_RequestGroupStatus");
	MarkNativeAsOptional("Steam_RequestGameplayStats");
	MarkNativeAsOptional("Steam_RequestServerReputation");
	MarkNativeAsOptional("Steam_IsConnected");
	MarkNativeAsOptional("Steam_SetRule");
	MarkNativeAsOptional("Steam_ClearRules");
	MarkNativeAsOptional("Steam_ForceHeartbeat");
	MarkNativeAsOptional("Steam_AddMasterServer");
	MarkNativeAsOptional("Steam_RemoveMasterServer");
	MarkNativeAsOptional("Steam_GetNumMasterServers");
	MarkNativeAsOptional("Steam_GetMasterServerAddress");
	MarkNativeAsOptional("Steam_SetGameDescription");
	MarkNativeAsOptional("Steam_RequestStats");
	MarkNativeAsOptional("Steam_GetStat");
	MarkNativeAsOptional("Steam_GetStatFloat");
	MarkNativeAsOptional("Steam_IsAchieved");
	MarkNativeAsOptional("Steam_GetNumClientSubscriptions");
	MarkNativeAsOptional("Steam_GetClientSubscription");
	MarkNativeAsOptional("Steam_GetNumClientDLCs");
	MarkNativeAsOptional("Steam_GetClientDLC");
	MarkNativeAsOptional("Steam_GetCSteamIDForClient");
	MarkNativeAsOptional("Steam_SetCustomSteamID");
	MarkNativeAsOptional("Steam_GetCustomSteamID");
	MarkNativeAsOptional("Steam_RenderedIDToCSteamID");
	MarkNativeAsOptional("Steam_CSteamIDToRenderedID");
	MarkNativeAsOptional("Steam_GroupIDToCSteamID");
	MarkNativeAsOptional("Steam_CSteamIDToGroupID");
	MarkNativeAsOptional("Steam_CreateHTTPRequest");
	MarkNativeAsOptional("Steam_SetHTTPRequestNetworkActivityTimeout");
	MarkNativeAsOptional("Steam_SetHTTPRequestHeaderValue");
	MarkNativeAsOptional("Steam_SetHTTPRequestGetOrPostParameter");
	MarkNativeAsOptional("Steam_SendHTTPRequest");
	MarkNativeAsOptional("Steam_DeferHTTPRequest");
	MarkNativeAsOptional("Steam_PrioritizeHTTPRequest");
	MarkNativeAsOptional("Steam_GetHTTPResponseHeaderSize");
	MarkNativeAsOptional("Steam_GetHTTPResponseHeaderValue");
	MarkNativeAsOptional("Steam_GetHTTPResponseBodySize");
	MarkNativeAsOptional("Steam_GetHTTPResponseBodyData");
	MarkNativeAsOptional("Steam_WriteHTTPResponseBody");
	MarkNativeAsOptional("Steam_ReleaseHTTPRequest");
	MarkNativeAsOptional("Steam_GetHTTPDownloadProgressPercent");

	// Mark cURL natives as optional
	MarkNativeAsOptional("curl_easy_init");
	MarkNativeAsOptional("curl_easy_setopt_string");
	MarkNativeAsOptional("curl_easy_setopt_int");
	MarkNativeAsOptional("curl_easy_setopt_int_array");
	MarkNativeAsOptional("curl_easy_setopt_int64");
	MarkNativeAsOptional("curl_OpenFile");
	MarkNativeAsOptional("curl_httppost");
	MarkNativeAsOptional("curl_slist");
	MarkNativeAsOptional("curl_easy_setopt_handle");
	MarkNativeAsOptional("curl_easy_setopt_function");
	MarkNativeAsOptional("curl_load_opt");
	MarkNativeAsOptional("curl_easy_perform");
	MarkNativeAsOptional("curl_easy_perform_thread");
	MarkNativeAsOptional("curl_easy_send_recv");
	MarkNativeAsOptional("curl_send_recv_Signal");
	MarkNativeAsOptional("curl_send_recv_IsWaiting");
	MarkNativeAsOptional("curl_set_send_buffer");
	MarkNativeAsOptional("curl_set_receive_size");
	MarkNativeAsOptional("curl_set_send_timeout");
	MarkNativeAsOptional("curl_set_recv_timeout");
	MarkNativeAsOptional("curl_get_error_buffer");
	MarkNativeAsOptional("curl_easy_getinfo_string");
	MarkNativeAsOptional("curl_easy_getinfo_int");
	MarkNativeAsOptional("curl_easy_escape");
	MarkNativeAsOptional("curl_easy_unescape");
	MarkNativeAsOptional("curl_easy_strerror");
	MarkNativeAsOptional("curl_version");
	MarkNativeAsOptional("curl_protocols");
	MarkNativeAsOptional("curl_features");
	MarkNativeAsOptional("curl_OpenFile");
	MarkNativeAsOptional("curl_httppost");
	MarkNativeAsOptional("curl_formadd");
	MarkNativeAsOptional("curl_slist");
	MarkNativeAsOptional("curl_slist_append");
	MarkNativeAsOptional("curl_hash_file");
	MarkNativeAsOptional("curl_hash_string");
}

//////////////////////////////
//		CLIENT FORWARDS		//
//////////////////////////////

public OnClientConnected(client)
{
	if(!IsFakeClient(client))
	{
		g_eClientState[client] = State_Waiting;
		g_iClientDuration[client] = 0;
	}
}

public OnClientDisconnect(client)
{
	g_eClientState[client] = State_Done;
	g_iClientDuration[client] = 0;
}

public OnClientPostAdminCheck(client)
{
	if(g_eClientState[client] == State_Viewing)
	{
		if(g_eCvars[g_cvarImmunityMode][aCache]==0 && GetUserFlagBits(client) & g_eCvars[g_cvarImmunityFlag][aCache])
		{
			// Blank out the page so if the ad was still playing it won't continue in the background
			Helper_SendMOTD(client, "Empty page", "about:blank", false);
			g_eClientState[client] = State_Done;

			// Continue the game if the ad was triggered by connecting
			if(g_eClientTrigger[client] == Connection)
				Helper_ContinueGame(client);
		}
	}
}

//////////////////////////////
//			COMMANDS		//
//////////////////////////////

public Action:Command_ClosedHTMLPage(client, const String:command[], argc)
{
	// Make sure the client is ingame and was watching an ad
	if(client && IsClientInGame(client))
	{
		if(g_bOriginalMOTD[client])
		{
				Helper_ContinueGame(client);
				return Plugin_Continue;
		}

		if(g_eClientState[client] == State_Done || (g_eClientState[client] == State_Viewing && GetTime() >= g_iClientDuration[client]+g_iClientAdStart[client]) || (g_eClientState[client] == State_Requesting && GetTime() >= g_iClientAdStart[client]+g_eCvars[g_cvarTimeout][aCache]) || GetUserFlagBits(client) & g_eCvars[g_cvarImmunityFlag][aCache])
		{
			g_eClientState[client] = State_Done;

			// Continue the game if the ad was triggered by connecting
			if(g_eClientTrigger[client] == Connection)
			{
				if(g_eCvars[g_cvarShowOriginal][aCache])
				{
						Helper_SendMOTD(client, g_szOriginalMOTDTitle[client], g_szOriginalMOTD[client], true, false, g_iOriginalMOTDType[client]);
						g_bOriginalMOTD[client] = true;
				}
				else
						Helper_ContinueGame(client);
			}
		}
		else
		{
			Helper_SendMOTD(client, MOTDGD_MOTD_TITLE, "");
		}
	}
	return Plugin_Continue;
}

//////////////////////////////
//			EVENTS			//
//////////////////////////////

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_eCvars[g_cvarRoundAds][aCache] != 1)
		return Plugin_Continue;

	LoopIngamePlayers(i)
		Helper_RequestAd(i);

	return Plugin_Continue;
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_eCvars[g_cvarRoundAds][aCache] != 2)
		return Plugin_Continue;

	LoopIngamePlayers(i)
		Helper_RequestAd(i);

	return Plugin_Continue;
}

public Action:Event_PlayerTransitioned(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!g_eCvars[g_cvarTransitionAds][aCache])
		return Plugin_Continue;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client && IsClientInGame(client))
		Helper_RequestAd(client);

	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!g_eCvars[g_cvarDeathAds][aCache])
		return Plugin_Continue;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client && IsClientInGame(client))
		Helper_RequestAd(client);

	return Plugin_Continue;
}

public Action:Event_PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client && IsClientInGame(client) && g_eClientState[client] == State_Viewing)
	{
		g_eClientState[client] = State_Done;
	}

	return Plugin_Continue;
}

//////////////////////////////
//			HOOKS			//
//////////////////////////////

public Action:Hook_VGUIMenu(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	// Check if we should show ads at all
	if(!g_eCvars[g_cvarConnectionAds][aCache])
		return Plugin_Continue;

	// Check if we only have one client who's not a bot and fully ingame and hasn't got immunity
	new client = players[0];
	if(playersNum > 1 || !client || !IsClientInGame(client))
		return Plugin_Continue;

	// Check if the client is waiting for an ad
	if(g_eClientState[client] != State_Waiting)
		return Plugin_Continue;

	// Make sure it's a MOTD window and not some other type of VGUI menu
	decl String:m_szName[64];
	decl String:m_szKey[64];
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
	{
		PbReadString(bf, "name", STRING(m_szName));
		new m_iSubkeys = PbGetRepeatedFieldCount(bf, "subkeys");
		for(new i=0;i<m_iSubkeys;++i)
		{
			new Handle:m_hMessage = PbReadMessage(bf, "subkeys");
			PbReadString(m_hMessage, "name", STRING(m_szKey));
			PbReadString(m_hMessage, "msg", g_szOriginalMOTD[client], 256);
			if(strcmp(m_szKey, "title")==0)
				strcopy(g_szOriginalMOTDTitle[client], sizeof(g_szOriginalMOTDTitle[]), g_szOriginalMOTD[client]);
			else if(strcmp(m_szKey, "type")==0)
		  		g_iOriginalMOTDType[client] = StringToInt(g_szOriginalMOTD[client]);
			else if(strcmp(m_szKey, "msg")==0)
				break;
		}
	}
	else
	{
		BfReadString(bf, STRING(m_szName));
		BfReadByte(bf);
		new m_iSubkeys = BfReadByte(bf);
		for(new i=0;i<m_iSubkeys;++i)
		{
			BfReadString(bf, STRING(m_szKey));
			BfReadString(bf, g_szOriginalMOTD[client], 256);
			if(strcmp(m_szKey, "title")==0)
				strcopy(g_szOriginalMOTDTitle[client], sizeof(g_szOriginalMOTDTitle[]), g_szOriginalMOTD[client]);
			else if(strcmp(m_szKey, "type")==0)
				g_iOriginalMOTDType[client] = StringToInt(g_szOriginalMOTD[client]);
			else if(strcmp(m_szKey, "msg")==0)
				break;
		}
	}

	if (strcmp(m_szName, "info") != 0)
			return Plugin_Continue;

	// Set the trigger
	g_eClientTrigger[client] = Connection;

	// Reset the g_bOriginalMOTD value for the client
	g_bOriginalMOTD[client] = false;

	// Show an ad to the client
	if(Helper_RequestAd(client))
		return Plugin_Handled;
	return Plugin_Continue;
}

//////////////////////////////
//			HELPERS			//
//////////////////////////////

public bool:Helper_RequestAd(client)
{
	// Do some sanity checks
	if(g_eCvars[g_cvarImmunityMode][aCache] && GetUserFlagBits(client) & g_eCvars[g_cvarImmunityFlag][aCache])
		return false;

	if(g_eClientState[client] == State_Requesting || g_eClientState[client] == State_Viewing)
		return false;

	// Check the cooldown
	if(g_iClientDuration[client]+g_iClientAdStart[client]+g_eCvars[g_cvarCooldown][aCache]*60 > GetTime())
		return false;

	// Set the default duration and ad start
	g_iClientAdStart[client] = GetTime();
	if(g_eCvars[g_cvarForcedDuration][aCache])
	{
		if(GetUserFlagBits(client) & g_eCvars[g_cvarImmunityFlag][aCache] && g_eCvars[g_cvarImmunityFlag][aCache] != 0)
			g_iClientDuration[client] = -1;
		else
			g_iClientDuration[client] = g_eCvars[g_cvarTimeout][aCache];

		// Ask the backend for the duration of the ad until we get it
		CreateTimer(1.0, Timer_GetAdStatus, GetClientUserId(client));
	}
	else
		g_iClientDuration[client] = 0;

	// Set the client state
	g_eClientState[client] = State_Requesting;

	// Show the MOTD to the client
	CreateTimer(0.0, Timer_DelayedSendMotd, GetClientUserId(client));

	return true;
}

public Action:Timer_DelayedSendMotd(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client))
		return Plugin_Stop;

	Helper_SendMOTD(client, MOTDGD_MOTD_TITLE, g_eCvars[g_cvarMotdUrl][sCache]);
	return Plugin_Stop;
}

public Action:Timer_GetAdStatus(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client))
		return Plugin_Stop;

	if(GetUserFlagBits(client) & g_eCvars[g_cvarImmunityFlag][aCache] || g_eClientState[client] == State_Done)
		return Plugin_Stop;

	// Format our request URL
	decl String:m_szRequestURL[512];
	new String:m_szSteamID[32] = "STEAM_1:0:0"; // May be uninitialized yet...
	decl String:m_szClientIP[16];

	GetClientAuthString(client, STRING(m_szSteamID));
	GetClientIP(client, STRING(m_szClientIP), true);

	Format(STRING(m_szRequestURL), "%s?ip=%s&pt=%d&v=%s&st=%s", MOTDGD_BACKEND_URL, g_szServerIP, g_iServerPort, PLUGIN_VERSION, m_szSteamID);

	// Request a customized ad for the client
	if(!EasyHTTP(m_szRequestURL, Helper_GetAdStatus_Complete, GetClientUserId(client)))
	{
		LogError("EasyHTTP request failed.");
		return Plugin_Stop;
	}

	return Plugin_Stop;
}

public Helper_GetAdStatus_Complete(any:userid, const String:buffer[], bool:success)
{
	// Make sure our client is still ingame
	new client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client))
		return;

	// Check if the request failed for whatever reason
	if(!success)
	{
		LogError("EasyHTTP request failed. Request reported failure.");
		Helper_ContinueGame(client);
		return;
	}

	// Decode the returned JSON
	new Handle:m_hJSON = DecodeJSON(buffer);
	if(m_hJSON == INVALID_HANDLE)
	{
		Helper_ContinueGame(client);
		return;
	}

	// Check if the backend has received the duration yet
	decl bool:m_bSuccess;
	if(!JSONGetBoolean(m_hJSON, "success", m_bSuccess) || !m_bSuccess)
	{
		if(g_iClientAdStart[client]+g_eCvars[g_cvarTimeout][aCache] <= GetTime())
			g_eClientState[client] = State_Done;
		else
			CreateTimer(1.0, Timer_GetAdStatus, GetClientUserId(client));
		DestroyJSON(m_hJSON);
		return;
	}

	// Set the duration the client will be viewing the ad for
	decl m_iStatus;
	JSONGetInteger(m_hJSON, "status", m_iStatus);

	if(m_iStatus == 1)
	{
		g_eClientState[client] = State_Viewing;
		if(g_iClientDuration[client] != -1)
			g_iClientDuration[client] = g_eCvars[g_cvarMaximumDuration][aCache];
		CreateTimer(1.0, Timer_GetAdStatus, GetClientUserId(client));
	}
	else if(m_iStatus == 2)
		g_iClientDuration[client] = -1;

	// Destroy the JSON handle
	DestroyJSON(m_hJSON);
}

stock Helper_SendMOTD(client, const String:title[], const String:url[], bool:show=true, bool:track=true, type=MOTDPANEL_TYPE_URL)
{
	new Handle:kv = CreateKeyValues("data");
	if(!g_bL4D && !g_bL4D2)
		KvSetNum(kv, "cmd", 5);
	else
		KvSetString(kv, "cmd", "closed_htmlpage");

	KvSetString(kv, "msg", url);
	KvSetString(kv, "title", title);
	KvSetNum(kv, "type", type);

	ShowVGUIPanel(client, "info", kv, show);
	CloseHandle(kv);

	if(show && track)
		CreateTimer(1.0, Timer_DisplayMotd, GetClientUserId(client));
}

public Helper_ContinueGame(client)
{
	g_eClientState[client] = State_Done;
	if(g_bCSS || g_bND)
		FakeClientCommand(client, "joingame");
	else if(g_bDOD)
		ClientCommand(client, "changeteam");
}

public Action:Timer_DisplayMotd(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client))
		return Plugin_Stop;

	if(GetUserFlagBits(client) & g_eCvars[g_cvarImmunityFlag][aCache] || g_eClientState[client] == State_Done)
		return Plugin_Stop;

	Helper_SendMOTD(client, MOTDGD_MOTD_TITLE, "");

	return Plugin_Stop;
}
