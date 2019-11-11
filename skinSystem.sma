#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <colorchat>
#include <hamsandwich>
#include <json>
#include <csx>

#define AUTHOR "Wicked - amxx.pl/user/60210-wicked/"


#define DEBUG


#pragma semicolon 1


#define MAX_CHARS 33
#define MAX_PLAYERS 32
#define MAX_SKINS 32


#define getUserMoney(%1) (cs_get_user_money(%1))
#define setUserMoney(%1,%2) (cs_set_user_money(%1, %2))


#define ForRange(%1,%2,%3) for(new %1 = %2; %1 <= %3; %1++)
#define ForArray(%1,%2) for(new %1 = 0; %1 < sizeof %2; %1++)
#define ForFile(%1,%2,%3,%4,%5) for(new %1 = 0; read_file(%2, %1, %3, %4, %5); %1++)
#define ForDynamicArray(%1,%2) for(new %1 = 0; %1 < ArraySize(%2); %1++)
#define ForSkins(%1) for(new %1 = 0; %1 <= MAX_SKINS - 1; %1++)


// Data enum.
enum skindata (+= 1)
{
	skindataModelV,
	skindataModelP,
	skindataName,
	skindataAccess,
	skindataCSW,
	skindataFrags,
	skindataCost
};


// Overall skins system prefix.
new const logPrefix[] = "[SKINS SYSTEM]";


// Path to .json file.
new const jsonFilePath[] = "addons/amxmodx/data/skinsData.json";


// Determines how many skins will be displayed in menu (change that to prevent menu-overflow).
const skinsPerPage = 5;


// Config file path.
new const configFilePath[] = "addons/amxmodx/configs/skinsConfig.ini";

// Forbidden characters in config file.
new const configFileForbiddenChars[][] =
{
	" ",
	";",
	"/",
	"\"
};


// Skins menu commands.
new const skinsMenuCommands[][] =
{
	"/skiny",
	"/skins"
};


new userSkin[MAX_PLAYERS + 1][MAX_SKINS],
	bool:userDataLoaded[MAX_PLAYERS + 1],

	Array:skinModel[2][MAX_SKINS],
	Array:skinName[MAX_SKINS],
	Array:skinAccess[MAX_SKINS],
	Array:skinCSW[MAX_SKINS],
	Array:skinFrags[MAX_SKINS],
	Array:skinCost[MAX_SKINS],

	JSON:jsonHandle;


public plugin_init()
{
	register_plugin("Skiny", "v1.2", AUTHOR);

	// Register every command.
	registerCommands(skinsMenuCommands, sizeof skinsMenuCommands, "weaponsMenu");

	// Get json handle.
	jsonHandle = json_parse(jsonFilePath, true, false);

	// Handle json object if invalid.
	if(jsonHandle == Invalid_JSON)
	{	
		jsonHandle = json_init_object();
	}

	#if defined DEBUG
	
	register_srvcmd("loadData", "srvcmdLoadData");

	register_clcmd("say /k", "addMoney");
	
	#endif
}

#if defined DEBUG

public addMoney(index)
{
	setUserMoney(index, 10000);
}

#endif

/*
		[ FORWARDS & MENUS ]
*/

public plugin_precache()
{
	createArrays();
	loadSkins();
	registerForwards();
}

public plugin_end()
{
	json_serial_to_file(jsonHandle, jsonFilePath, true);

	json_free(jsonHandle);
}

public weaponsMenu(index)
{
	new	menuIndex = menu_create("Wybierz bron:", "weaponsMenu_handler"),
		item[MAX_CHARS * 2];

	// Loop through every weapon id, add name to menu if at least one was found.
	ForSkins(i)
	{
		// Continue if there are none skins for that weapon.
		if(!ArraySize(skinName[i]))
		{
			continue;
		}

		// Get weapon name to upper case and without 'weapon_' prefix.
		getWeaponName(i, item, charsmax(item));

		// Add data to menu.
		menu_additem(menuIndex, fmt("%s - skinow: %i", item, ArraySize(skinName[i])), fmt("%i", i));
	}

	menu_display(index, menuIndex);

	return PLUGIN_HANDLED;
}

public weaponsMenu_handler(index, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu);
		
		return PLUGIN_HANDLED;
	}

	new readData[4];

	// Read menu data.
	menu_item_getinfo(menu, item, _, readData, charsmax(readData));

	menu_destroy(menu);

	// Let user choose the skin he wants.
	skinsMenu(index, str_to_num(readData));

	return PLUGIN_HANDLED;
}

public skinsMenu(index, csw)
{
	new item[MAX_CHARS + 8],
		menuIndex,
		stats[8],
		blank[8],
		hasAccess[2],

		skinFlags,
		skinFragsData,
		skinCostData,

		costData[25],
		fragsData[25];

	// Get skin name if not default.
	if(userSkin[index][csw] != -1)
	{
		ArrayGetString(skinName[csw], userSkin[index][csw], item, charsmax(item));
	}
	
	// Create menu handler.
	menuIndex = menu_create(fmt("Aktualny skin:\w %s\y^nWybierz nowego skina:", userSkin[index][csw] > -1 ? item : "Brak"), "skinsMenu_handler");

	// Add formated data as menu item.
	menu_additem(menuIndex, "Domyslny", fmt("1#0#%i", csw));

	// Loop through every skin assigned to CSW_ index and add it's data to menu item.
	ForDynamicArray(i, skinName[csw])
	{
		// Get skin access-data.
		skinFlags = ArrayGetCell(skinAccess[csw], i);
		skinFragsData = ArrayGetCell(skinFrags[csw], i);
		skinCostData = ArrayGetCell(skinCost[csw], i);

		// Get skin name.
		ArrayGetString(skinName[csw], i, item, charsmax(item));

		// Get user stats to check frags.
		get_user_stats(index, stats, blank);

		// User has access to that skin?
		getSkinAccess(hasAccess, index, skinFlags, skinFragsData, skinCostData, item);

		if(skinFragsData)
		{
			formatex(fragsData, charsmax(fragsData), " Od: %i fragow", skinFragsData);
		}

		if(skinCostData)
		{
			formatex(costData, charsmax(costData), " Koszt: %i", skinCostData);
		}

		// Add data to menu.
		menu_additem(menuIndex, fmt("%s%s%s%s", hasAccess[0] ? "\w" : "\r", item, fragsData, costData), fmt("%i#%i#%i", hasAccess[0], hasAccess[1], csw));
	}

	menu_setprop(menuIndex, MPROP_PERPAGE, skinsPerPage);

	menu_display(index, menuIndex);

	return PLUGIN_HANDLED;
}

public skinsMenu_handler(index, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu);
		
		return PLUGIN_HANDLED;
	}

	new readData[16],
		intData[10][10],
		weaponIndex,

		skinDataInt[4];

	// Read menu data.
	menu_item_getinfo(menu, item, _, readData, charsmax(readData));
	
	menu_destroy(menu);

	// Get no-access data from menu info.
	split(readData, intData[0], charsmax(intData[]), intData[1], charsmax(intData[]), "#");
	split(intData[1], intData[1], charsmax(intData[]), intData[2], charsmax(intData[]), "#");

	// Convert string-data to integers.
	ForRange(i, 0, 2)
	{
		skinDataInt[i] = str_to_num(intData[i]);
	}

	// Return if user has no access.
	if(!skinDataInt[0])
	{
		ColorChat(index, RED, "%s^x01 Nie masz dostepu do tego skina. %s.", logPrefix, (skinDataInt[1] == 1 ? "Brakuje Ci fragow" : (skinDataInt[1] == 2 ? "Skin jest za drogi" : "Brakuje Ci flag")));
	
		return PLUGIN_HANDLED;
	}

	new chosenWeaponName[MAX_CHARS];

	// Get CSW_ index.
	weaponIndex = skinDataInt[2];

	// Get chosen weapon name.
	getWeaponName(weaponIndex, chosenWeaponName, charsmax(chosenWeaponName));

	// Set user skin to chosen one.
	userSkin[index][weaponIndex] = !item ? -1 : item - 1;

	// Notify about skin being set to chosen one.
	if(!item)
	{
		ColorChat(index, RED, "%s^x01 Ustawiles domyslnego skina dla ^"^x03%s^x01^".", logPrefix, chosenWeaponName);
	}
	else
	{
		new chosenSkinName[MAX_CHARS];

		ArrayGetString(skinName[weaponIndex], userSkin[index][weaponIndex], chosenSkinName, charsmax(chosenSkinName));

		if(skinDataInt[0] == 1)
		{
			new cost = ArrayGetCell(skinCost[weaponIndex], userSkin[index][weaponIndex]);

			setUserMoney(index, getUserMoney(index) - cost);

			ColorChat(index, RED, "%s^x01 Kupiles skina ^"^x03%s^x01^" dla broni ^"^x03%s^x01^" za^x03 %i^x01.", logPrefix, chosenSkinName, chosenWeaponName, cost);

			saveUserSkins(index);
		}
		else
		{
			ColorChat(index, RED, "%s^x01 Ustawiles skina ^"^x03%s^x01^" dla broni ^"^x03%s^x01^".", logPrefix, chosenSkinName, chosenWeaponName);
		}
	}

	// Set new model if his current weapon is the one he just changed skin on.
	if(get_user_weapon(index) == weaponIndex)
	{
		setViewmodel(index, weaponIndex);
	}

	return PLUGIN_HANDLED;
}

public weaponDeploy(entity)
{
	new index = pev(entity, pev_owner),
		weapon = cs_get_weapon_id(entity);

	// Return if player isnt alive or his skin is default.
	if(!is_user_alive(index) || userSkin[index][weapon] == -1)
	{
		return;
	}

	setViewmodel(index, weapon);
}

// Get skins data.
public client_putinserver(index)
{
	setNoSkins(index);

	loadUserSkins(index);
}

// Save user skins data.
public client_disconnect(index)
{
	saveUserSkins(index);
}

/*
		[ FUNCTIONS ]
*/

bool:getSkinAccess(accessArray[], index, flags, frags, cost, name[] = "")
{
	accessArray[0] = 1;

	if(hasSkin(index, name))
	{
		accessArray[0] = 2;

		return true;
	}

	if(frags)
	{
		new userStats[8],
			userStatsBlank[8];

		get_user_stats(index, userStats, userStatsBlank);

		if(userStats[0] < frags)
		{
			accessArray[0] = 0;
			accessArray[1] = 1;

			return false;
		}
	}

	if(cost && getUserMoney(index) < cost)
	{
		accessArray[0] = 0;
		accessArray[1] = 2;

		return false;
	}

	if(flags && !(get_user_flags(index) & flags))
	{
		accessArray[0] = 0;
		accessArray[1] = 3;

		return false;
	}

	return true;
}

setViewmodel(index, weapon)
{
	if(userSkin[index][weapon] == -1)
	{
		return;
	}

	new weaponModel[2][MAX_CHARS];

	// Get model paths.
	ForRange(i, 0, 1)
	{
		if(ArraySize(skinModel[i][weapon]))
		{
			ArrayGetString(skinModel[i][weapon], userSkin[index][weapon], weaponModel[i], charsmax(weaponModel[]));
		}

		if(!strlen(weaponModel[i]))
		{
			continue;
		}

		// Set model on user screen if model is present.
		set_pev(index, i ? pev_weaponmodel2 : pev_viewmodel2, weaponModel[i]);
	}
}

// Set every skin to -1 (default).
setNoSkins(index)
{
	ForRange(i, 0, MAX_SKINS - 1)
	{
		userSkin[index][i] = -1;
	}
}

registerForwards()
{
	new entityName[MAX_CHARS];

	// Loop through every skin and register weaponDeploy event to it's weapon classname.
	ForRange(i, 0, MAX_SKINS - 1)
	{
		if(!ArraySize(skinName[i]))
		{
			continue;
		}

		get_weaponname(i, entityName, charsmax(entityName));

		if(entityName[0])
		{
			RegisterHam(Ham_Item_Deploy, entityName, "weaponDeploy", true);
		}
	}
}

getWeaponName(csw, string[], length)
{
	// Get 'weapon_' name.
	get_weaponname(csw, string, length);
	
	// Clamp down name to get rid of the 'weapon_' prefix.
	format(string, length, string[7]);

	// Get name to upper case.
	strtoupper(string);
}

loadSkins()
{
	new lineData[MAX_CHARS * 8],
		lineLength,
		bool:lineContinue,
		lineDataArguments[9][MAX_CHARS * 3],

		skinCswIndex,
		skinFlagsData,
		skinFragsData,
		skinCostData,

		filePath[128];

	ForFile(i, configFilePath, lineData, charsmax(lineData), lineLength)
	{
		// Continue if nothing was found on line.
		if(!lineData[0])
		{
			continue;
		}

		lineContinue = false;

		// Loop through forbidden characters to prevent headache.
		ForArray(i, configFileForbiddenChars)
		{
			if(lineData[0] == configFileForbiddenChars[i][0])
			{
				lineContinue = true;

				break;
			}
		}

		// Continue main loop if found at least one forbidden character on current line.
		if(lineContinue)
		{
			continue;
		}

		// Parse line data to strings.
		parse(lineData,
			lineDataArguments[skindataModelV], charsmax(lineDataArguments[]),
			lineDataArguments[skindataModelP], charsmax(lineDataArguments[]),
			lineDataArguments[skindataName], charsmax(lineDataArguments[]),
			lineDataArguments[skindataAccess], charsmax(lineDataArguments[]),
			lineDataArguments[skindataCSW], charsmax(lineDataArguments[]),
			lineDataArguments[skindataFrags], charsmax(lineDataArguments[]),
			lineDataArguments[skindataCost], charsmax(lineDataArguments[]));
	
		// Get CSW_ index.
		skinCswIndex = str_to_num(lineDataArguments[skindataCSW]);

		// Get both P_ and V_ model for weapon. Break loop and continue main loop if file was not present.
		ForRange(i, 0, 1)
		{
			// Continue if model's name length is 0.
			if(!lineDataArguments[skindata:i][0])
			{
				continue;
			}

			// Handle "/models" and ".mdl" formatting.
			format(filePath, charsmax(filePath), "%s%s%s", containi(lineDataArguments[skindata:i], "models/") == -1 ? "models/" : "", lineDataArguments[skindata:i], containi(lineDataArguments[skindata:i], ".mdl") == -1 ? ".mdl" : "");

			if(!file_exists(filePath))
			{
				log_amx("%s ERROR: weapon model %s not found on path (^"%s^").", logPrefix, i ? "P" : "V", filePath);

				lineContinue = true;
			}

			// Break out of loop if model file was not found.
			if(lineContinue)
			{
				continue;
			}

			// Add that model to dynamic array.
			ArrayPushString(skinModel[i][skinCswIndex], filePath);

			precache_model(filePath);

			#if defined DEBUG

			log_amx("Precaching file: ^"%s^"", filePath);

			#endif
		}

		// Continue main loop if at least one model was not found.
		if(lineContinue)
		{
			continue;
		}
		
		// Get skin-access data.
		skinFlagsData = (lineDataArguments[skindataAccess][0] == '0' || !lineDataArguments[skindataAccess]) ? 0 : read_flags(lineDataArguments[skindataAccess]);
		skinFragsData = str_to_num(lineDataArguments[skindataFrags]);
		skinCostData = str_to_num(lineDataArguments[skindataCost]);

		// Get skin name, access and weapon index.
		ArrayPushString(skinName[skinCswIndex], lineDataArguments[skindataName]);
		ArrayPushCell(skinAccess[skinCswIndex], skinFlagsData);
		ArrayPushCell(skinCSW[skinCswIndex], skinCswIndex);
		ArrayPushCell(skinFrags[skinCswIndex], skinFragsData);
		ArrayPushCell(skinCost[skinCswIndex], skinCostData);

		#if defined DEBUG
		
		// Log currently processed skin data.
		log_amx("%s Added: ^"%s^". Data: (V: ^"%s^") (P: ^"%s^") (Access: (Flags: ^"%s^" (%i)) (CSW: %i) (Cost: %i) (Frags: %i)).",
				logPrefix,
				lineDataArguments[skindataName],
				lineDataArguments[skindataModelV],
				lineDataArguments[skindataModelP],
				lineDataArguments[skindataAccess],
				skinFlagsData,
				skinCswIndex,
				skinCostData,
				skinFragsData);
		
		#endif
	}
}

createArrays()
{
	// Loop through every weapon id and create dynamic arrays. Since this is created before config file is loaded, we can do nothing to prevent data lose by creating arrays which will never be used.
	ForSkins(i)
	{
		ForRange(j, 0, 1)
		{
			skinModel[j][i] = ArrayCreate(MAX_CHARS, 1);
		}

		skinName[i] = ArrayCreate(MAX_CHARS, 1);
		skinAccess[i] = ArrayCreate(1, 1);
		skinCSW[i] = ArrayCreate(1, 1);
		skinFrags[i] = ArrayCreate(1, 1);
		skinCost[i] = ArrayCreate(1, 1);
	}
}

saveUserDataInt(index, label[], data, bool:dotNotation = true)
{
	if(!is_user_connected(index) || !userDataLoaded[index])
	{
		return -1;
	}

	return json_object_set_number(jsonHandle, fmt("%n.%s", index, label), data, dotNotation);
}

getUserDataInt(index, label[], bool:dotNotation = true)
{
	if(!is_user_connected(index) && !is_user_connecting(index))
	{
		return -1;
	}

	userDataLoaded[index] = true;

	return json_object_get_number(jsonHandle, fmt("%n.%s", index, label), dotNotation);
}

// BUG: this plugin only saves current weapon, not list of skins, so problem of saving list of skins instead of just the current one remains unsolved.
bool:hasSkin(index, name[])
{
	return bool:(json_object_has_value(jsonHandle, fmt("%n.%s", index, name), _, true) ? (getUserDataInt(index, name, true) > -1 ? true : false) : false);
}

stock registerCommands(const array[][], arraySize, function[])
{
	#if !defined ForRange

		#define ForRange(%1,%2,%3) for(new %1 = %2; %1 <= %3; %1++)

	#endif

	#if AMXX_VERSION_NUM < 183
	
	ForRange(i, 0, arraySize - 1)
	{
		ForRange(j, 0, 1)
		{
			register_clcmd(fmt("%s %s", !j ? "say" : "say_team", array[i]), function);
		}
	}

	#else

	new newCommand[MAX_CHARS];

	ForRange(i, 0, arraySize - 1)
	{
		ForRange(j, 0, 1)
		{
			formatex(newCommand, charsmax(newCommand), "%s %s", !j ? "say" : "say_team", array[i]);
			register_clcmd(newCommand, function);
		}
	}

	#endif
}

/*
		[ DATABASE ]
*/

loadUserSkins(index)
{
	if(!is_user_connected(index))
	{
		return;
	}

	new weaponName[MAX_CHARS];

	ForSkins(i)
	{
		if(!ArraySize(skinName[i]))
		{
			continue;
		}

		getWeaponName(i, weaponName, charsmax(weaponName));

		if(!json_object_has_value(jsonHandle, fmt("%n.%s", index, weaponName), _, true))
		{
			userSkin[index][i] = -1;

			continue;
		}

		userSkin[index][i] = getUserDataInt(index, weaponName);
	}
}

saveUserSkins(index)
{
	if(!is_user_connected(index))
	{
		return;
	}

	new weaponName[MAX_CHARS];

	ForSkins(i)
	{
		if(!ArraySize(skinName[i]))
		{
			continue;
		}

		getWeaponName(i, weaponName, charsmax(weaponName));

		saveUserDataInt(index, weaponName, userSkin[index][i]);
	}
}

/*
		[ USELESS STUFF ]
*/

#if defined DEBUG

public srvcmdLoadData()
{
	printArrays();
}

public printArrays()
{
	new skinsData[3][MAX_CHARS],
		flags,
		cswIndex;

	ForSkins(i)
	{
		if(!ArraySize(skinName[i]))
		{
			continue;
		}

		ForDynamicArray(j, skinName[i])
		{
			ArrayGetString(skinModel[0][i], j, skinsData[0], charsmax(skinsData[]));

			ArrayGetString(skinName[i], j, skinsData[2], charsmax(skinsData[]));
			flags = ArrayGetCell(skinAccess[i], j);
			cswIndex = ArrayGetCell(skinCSW[i], j);

			log_amx("Skin data: (Model V: ^"%s^") (Name: ^"%s^") (Access: ^"%i^") (CSW: %i).", skinsData[0], skinsData[2], flags, cswIndex);
		}
	}
}

#endif
