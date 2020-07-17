#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smlib/clients>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>


#define UPGRADE_SHORTNAME "bash"

ConVar g_hCVDefaultPercent;
ConVar g_hCVDefaultBashTime;
ConVar g_hCVDefaultMinDame;

enum WeaponConfig {
	Float:Weapon_BashChance,
	Float:Weapon_BashTime,
	Float:Weapon_MinDame
};

StringMap g_hWeaponDamage;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Bash",
	author = "LongPC",
	description = "Bash upgrade for SM:RPG. Give player weapon chance to freeze when damage on enemies.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	g_hWeaponDamage = new StringMap();

	// Account for late loading
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		SMRPG_RegisterUpgradeType("Bash", UPGRADE_SHORTNAME, "Give player weapon chance to freeze when damage on enemies.", 0, true, 5, 5, 10);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVDefaultPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bash_percent", "0.05", "Percentage of bash when damage done the victim", _, true, 0.0);
		g_hCVDefaultBashTime = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bash_time", "0.5", "Bash time that freeze victim", _, true, 0.0);
		g_hCVDefaultMinDame = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_bash_mindame", "15", "Min dame to trigger this effect", _, true, 0.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnMapStart()
{
	if(!LoadWeaponConfig())
		SetFailState("Can't read config file in configs/smrpg/bash_weapons.cfg!");
}

/**
 * SM:RPG Upgrade callbacks
 */

public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

/**
 * Hook callbacks
 */
public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return Plugin_Continue;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run

	int iLevel = SMRPG_GetClientUpgradeLevel(attacker, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return Plugin_Continue;
	
	char sWeapon[256];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));

	if (damage < GetWeaponBashTriggerMinDame(sWeapon)) {
		return Plugin_Continue;
	}
	if (StrContains(sWeapon, "hegrenade") != -1) {
		return Plugin_Continue;
	}
	
	float chanceToStun = GetWeaponBashChance(sWeapon);
	if (GetURandomFloat() > chanceToStun * iLevel)
		return Plugin_Continue;
	SMRPG_FreezeClient(victim, GetWeaponBashTime(sWeapon), 0.0, UPGRADE_SHORTNAME);
	CreateTimer(GetWeaponBashTime(sWeapon), ResetBash, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
	Client_PrintToChatAll(false, "{RB}%N{N} nhân phẩm tốt chạy hiệu ứng {B}%s{N} với {OG}%N{N}", attacker, UPGRADE_SHORTNAME, victim);
	return Plugin_Continue;
}
public Action ResetBash(Handle hTimer, any userId) {
	int client = GetClientOfUserId(userId);
	SMRPG_ResetUpgradeEffectOnClient(client, UPGRADE_SHORTNAME);
}

/**
 * Helpers
 */
bool LoadWeaponConfig()
{
	g_hWeaponDamage.Clear();
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/smrpg/bash_weapons.cfg");
	
	if(!FileExists(sPath))
		return false;
	
	KeyValues hKV = new KeyValues("BashWeapons");
	if(!hKV.ImportFromFile(sPath))
	{
		delete hKV;
		return false;
	}
	
	char sWeapon[64];
	if(hKV.GotoFirstSubKey(false))
	{
		int eInfo[WeaponConfig];
		do
		{
			hKV.GetSectionName(sWeapon, sizeof(sWeapon));
			
			eInfo[Weapon_BashChance] = hKV.GetFloat("bash_chance", -1.0);
			eInfo[Weapon_BashTime] = hKV.GetFloat("bash_time", -1.0);
			eInfo[Weapon_MinDame] = hKV.GetFloat("bash_mindame", -1.0);
			
			g_hWeaponDamage.SetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig));
			
		} while (hKV.GotoNextKey());
	}
	
	delete hKV;
	return true;
}

float GetWeaponBashChance(const char[] sWeapon)
{
	int eInfo[WeaponConfig];
	if (g_hWeaponDamage.GetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig)))
	{
		if (eInfo[Weapon_BashChance] >= 0.0)
			return eInfo[Weapon_BashChance];
	}
	
	// Just use the default value
	return g_hCVDefaultPercent.FloatValue;
}

float GetWeaponBashTime(const char[] sWeapon)
{
	int eInfo[WeaponConfig];
	if (g_hWeaponDamage.GetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig)))
	{
		if (eInfo[Weapon_BashTime] >= 0.0)
			return eInfo[Weapon_BashTime];
	}
	
	// Just use the default value
	return g_hCVDefaultBashTime.FloatValue;
}

float GetWeaponBashTriggerMinDame(const char[] sWeapon)
{
	int eInfo[WeaponConfig];
	if (g_hWeaponDamage.GetArray(sWeapon, eInfo[0], view_as<int>(WeaponConfig)))
	{
		if (eInfo[Weapon_MinDame] >= 0.0)
			return eInfo[Weapon_MinDame];
	}
	
	// Just use the default value
	return g_hCVDefaultMinDame.FloatValue;
}