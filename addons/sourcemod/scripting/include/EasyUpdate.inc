#if defined _easyupdate_included
 #endinput
#endif
#define _easyupdate_included

#include <easyjson>
#include <easyhttp>

new g_iUpdatedFiles = 0;

public EasyUpdate(const String:url[])
{
	if(!EasyHTTP(url, EasyUpdate_GetVersionDefinition, 0))
		LogError("EasyUpdate failed due to an error of EasyHTTP.");
}

public EasyUpdate_GetVersionDefinition(any:userid, const String:buffer[], bool:success)
{
	if(!success)
	{
		LogError("EasyUpdate failed due to receiving error.");
		return;
	}

	new Handle:m_hJSON = DecodeJSON(buffer);
	if(m_hJSON == INVALID_HANDLE)
	{
		LogError("EasyUpdate failed due to wrong version definition format.");
		return;
	}

	decl String:m_szCurrentVersion[32];
	decl String:m_szVersion[32];
	if(!GetPluginInfo(INVALID_HANDLE, PlInfo_Version, STRING(m_szCurrentVersion)))
	{
		LogError("EasyUpdate failed. Can't get plugin version.");
		DestroyJSON(m_hJSON);
		return;
	}

	if(!JSONGetString(m_hJSON, "version", STRING(m_szVersion)))
	{
		LogError("EasyUpdate failed. Version info is missing in definition.");
		DestroyJSON(m_hJSON);
		return;
	}

	if(strcmp(m_szCurrentVersion, m_szVersion)==0)
	{
		DestroyJSON(m_hJSON);
		return;
	}

	new Handle:m_hFiles = INVALID_HANDLE;
	if(!JSONGetObject(m_hJSON, "files", m_hFiles))
	{
		LogError("EasyUpdate failed. File list doesn't exist.");
		DestroyJSON(m_hJSON);
		return;
	}

	LogMessage("New version of plugin found, updating. (Old = %s, New = %s)", m_szCurrentVersion, m_szVersion);

	new Handle:m_hKeyArray = INVALID_HANDLE;
	GetTrieValue(m_hFiles, "json_key_array", m_hKeyArray);
	new m_iKeys = GetArraySize(m_hKeyArray);
	decl String:m_szKey[512];
	decl String:m_szValue[512];
	decl String:m_szFile[PLATFORM_MAX_PATH];
	for(new i=0;i<m_iKeys;++i)
	{
		GetArrayString(m_hKeyArray, i, STRING(m_szKey));
		if(!JSONGetString(m_hFiles, m_szKey, STRING(m_szValue)))
			continue;
		BuildPath(Path_SM, STRING(m_szFile), m_szKey);
		LogMessage("Downloading file %s", m_szKey);
		EasyHTTP(m_szValue, EasyUpdate_Complete, m_iKeys, m_szFile);
	}

	DestroyJSON(m_hJSON);
}

public EasyUpdate_Complete(any:data, const String:buffer[], bool:success)
{
	++g_iUpdatedFiles;
	if(g_iUpdatedFiles == data)
	{
		decl String:m_szFilename[PLATFORM_MAX_PATH];
		GetPluginFilename(INVALID_HANDLE, STRING(m_szFilename));
		m_szFilename[strlen(m_szFilename)-4] = 0;
		ServerCommand("sm plugins reload %s", m_szFilename);
	}
}