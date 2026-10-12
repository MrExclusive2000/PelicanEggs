<?php

return [
    // Where SCUM keeps its server configuration (relative to the server root).
    'config_dir' => 'SCUM/Saved/Config/WindowsServer',

    // Folder that holds SCUMServer.exe, dwmapi.dll and the ue4ss folder.
    'binaries_dir' => 'SCUM/Binaries/Win64',

    // How many ServerSettings.ini backups to keep before the oldest are deleted.
    'backups_to_keep' => (int) env('SCUM_MANAGER_BACKUPS_TO_KEEP', 10),

    // UE4SS build to install: "experimental" (recommended for SCUM) or "stable".
    'ue4ss_channel' => env('SCUM_MANAGER_UE4SS_CHANNEL', 'experimental'),

    // Optional direct download URL for a UE4SS zip. Overrides the channel when set.
    'ue4ss_url' => env('SCUM_MANAGER_UE4SS_URL'),

    // Install the mods that ship with the plugin (resources/mods) together with a fresh UE4SS install.
    'install_bundled_mods' => (bool) env('SCUM_MANAGER_INSTALL_BUNDLED_MODS', true),

    // Where "Install our mods" gets the latest mod zips (manifest.json and <Mod>.zip, checked by
    // sha256). Empty = only the copies bundled with the plugin. The bundled copies are also the
    // fallback when this cannot be reached.
    'mods_source' => env('SCUM_MANAGER_MODS_SOURCE', 'https://raw.githubusercontent.com/MrExclusive2000/PelicanEggs/HEAD/mods/dist'),

    // Limits for uploaded mod archives.
    'mod_upload_max_kb' => (int) env('SCUM_MANAGER_MOD_UPLOAD_MAX_KB', 51200),
    'mod_max_extracted_bytes' => 200 * 1024 * 1024,
    'mod_max_files' => 2000,
];
