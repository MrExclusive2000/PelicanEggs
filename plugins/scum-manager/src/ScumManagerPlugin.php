<?php

namespace MrExclusive\ScumManager;

use App\Contracts\Plugins\HasPluginSettings;
use App\Traits\EnvironmentWriterTrait;
use Filament\Contracts\Plugin;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Panel;

class ScumManagerPlugin implements HasPluginSettings, Plugin
{
    use EnvironmentWriterTrait;

    public function getId(): string
    {
        return 'scum-manager';
    }

    public function register(Panel $panel): void
    {
        $id = str($panel->getId())->title();

        $panel->discoverPages(plugin_path($this->getId(), "src/Filament/$id/Pages"), "MrExclusive\\ScumManager\\Filament\\$id\\Pages");
    }

    public function boot(Panel $panel): void {}

    public function getSettingsForm(): array
    {
        return [
            TextInput::make('backups_to_keep')
                ->label('ServerSettings.ini backups to keep')
                ->integer()
                ->minValue(1)
                ->maxValue(100)
                ->required(),
            Select::make('ue4ss_channel')
                ->label('UE4SS build')
                ->helperText('The experimental build is the one SCUM mod authors test against.')
                ->options([
                    'experimental' => 'Experimental (recommended)',
                    'stable' => 'Stable 3.0.x',
                ])
                ->selectablePlaceholder(false)
                ->required(),
            TextInput::make('ue4ss_url')
                ->label('UE4SS download URL override')
                ->helperText('Optional. A direct link to a UE4SS zip, used instead of the build above.')
                ->url()
                ->endsWith('.zip'),
            TextInput::make('mod_upload_max_kb')
                ->label('Max mod upload size (KB)')
                ->integer()
                ->minValue(1)
                ->required(),
        ];
    }

    public function getSettingsFormData(): array
    {
        return [
            'backups_to_keep' => config('scum-manager.backups_to_keep'),
            'ue4ss_channel' => config('scum-manager.ue4ss_channel'),
            'ue4ss_url' => config('scum-manager.ue4ss_url'),
            'mod_upload_max_kb' => config('scum-manager.mod_upload_max_kb'),
        ];
    }

    public function saveSettings(array $data): void
    {
        $this->writeToEnvironment([
            'SCUM_MANAGER_BACKUPS_TO_KEEP' => $data['backups_to_keep'],
            'SCUM_MANAGER_UE4SS_CHANNEL' => $data['ue4ss_channel'],
            'SCUM_MANAGER_UE4SS_URL' => $data['ue4ss_url'] ?? '',
            'SCUM_MANAGER_MOD_UPLOAD_MAX_KB' => $data['mod_upload_max_kb'],
        ]);

        Notification::make()
            ->title('Settings saved')
            ->success()
            ->send();
    }
}
