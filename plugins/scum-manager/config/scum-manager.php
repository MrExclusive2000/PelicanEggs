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

    // Limits for uploaded mod archives.
    'mod_upload_max_kb' => (int) env('SCUM_MANAGER_MOD_UPLOAD_MAX_KB', 51200),
    'mod_max_extracted_bytes' => 200 * 1024 * 1024,
    'mod_max_files' => 2000,
];
