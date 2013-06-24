#pragma semicolon 1

#define MOTD_TITLE "MOTDGD AD"
#define PLUGIN_VERSION "1.03"

#include <sourcemod>

new Handle:cvImmunity = INVALID_HANDLE;
new Handle:cvMotdUrl = INVALID_HANDLE;
new iServerPort = -1;
new iVGUICaught[MAXPLAYERS + 1] = { 0, ... };

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
	// Initialize our ConVars
	cvImmunity = CreateConVar("sm_motdgd_immunity", "1", "Whether ADMIN_GENERIC players are immune to MOTDgd advertisements");
	cvMotdUrl = CreateConVar("sm_motdgd_url", "", "The MOTD URL found on Your Portal Dashboard at motdgd.com");
	AutoExecConfig(true);

	CreateConVar("sm_motdgd_version", PLUGIN_VERSION, "MOTDgd Plugin Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// Initialize our global variables
	new Handle:h_hostIP = FindConVar("hostip");
	new Handle:h_hostPort = FindConVar("hostport");
	if(h_hostIP == INVALID_HANDLE || h_hostPort == INVALID_HANDLE)
		SetFailState("Failed to determine server ip and port.");

	iServerPort = GetConVarInt(h_hostPort);

	new iServerIP = GetConVarInt(h_hostIP);
	Format(sServerIPPort, sizeof(sServerIPPort), "%d.%d.%d.%d.%d", iServerIP >>> 24 & 255, iServerIP >>> 16 & 255, iServerIP >>> 8 & 255, iServerIP & 255, iServerPort);

	// Intercept the MOTD window and show our ad instead
	new UserMsg:umVGUIMenu = GetUserMessageId("VGUIMenu");
	if (umVGUIMenu == INVALID_MESSAGE_ID)
		SetFailState("This game doesn't support VGUI menus.");
	HookUserMessage(umVGUIMenu, Hook_VGUIMenu, true);
	AddCommandListener(ClosedHTMLPage, "closed_htmlpage");
}

public OnConfigsExecuted()
{
	
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
        iVGUICaught[client] = 0;
	
        return true;
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("GetUserMessageType");
}

public Action:Hook_VGUIMenu(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	new client = players[0];
	if(playersNum > 1 || !client || !IsClientInGame(client))
		return Plugin_Continue;
	
	// Skip if the player's MOTD has been intercepted
	if (iVGUICaught[client] > 0)
		return Plugin_Continue;
	
	decl String:sName[64];
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
		PbReadString(bf, sName, "name", sizeof(sName));
	else
		BfReadString(bf, sName, sizeof(sName));

	if (strcmp(sName, "info") != 0)
		return Plugin_Continue;
	
	// Don't repeat the interception more than once
	iVGUICaught[client] = 1;
	
	// If the player has ADMIN_GENERIC and immunity cvar is set to 1 then don't show them MOTDgd
	if (!CanViewMOTDgd(client) && GetConVarInt(cvImmunity) == 1)
		return Plugin_Continue;
	
	// Display MOTDgd
	CreateTimer(0.2, NewMOTD, client);

	return Plugin_Handled;
}

public Action:ClosedHTMLPage(client, const String:command[], argc)
{
	if (client && IsClientInGame(client) && !IsValidTeam(client))
	{
		// To ensure player can choose a team after closing the MOTD
		FakeClientCommand(client, "joingame");
	}
	
	return Plugin_Continue;
}

public Action:NewMOTD(Handle:timer, any:client)
{
	decl String:sURL[192];
	GetConVarString(cvMotdUrl, sURL, sizeof(sURL));
	SendMOTD(client, MOTD_TITLE, sURL);
}

stock SendMOTD(client, const String:title[], const String:url[], bool:show=true)
{
	new Handle:kv = CreateKeyValues("data");
	KvSetNum(kv, "cmd", 5);
	
	decl String:clientAuth[64];
	GetClientAuthString(client, clientAuth, sizeof(clientAuth));
	
	decl String:sURL[128];
	Format(sURL, sizeof(sURL), "%s&ipp=%s&v=%s&st=%s", url, sServerIPPort, PLUGIN_VERSION, clientAuth);
	
	KvSetString(kv, "msg", sURL);
	KvSetString(kv, "title", title);
	KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);

	ShowVGUIPanel(client, "info", kv, show);
	CloseHandle(kv);
}

bool:IsValidTeam(client)
{
	return (GetClientTeam(client) != 0);
}

stock bool:CanViewMOTDgd( client )
{
	new AdminId:aId = GetUserAdmin( client );
	
	if ( aId == INVALID_ADMIN_ID )
		return true;
	
	if ( GetAdminFlag( aId, Admin_Generic ) )
		return false;
		
	return true;
}
