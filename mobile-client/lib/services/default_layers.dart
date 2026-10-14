import '../models/layer.dart';
import '../models/macro_action.dart';
import '../models/macro_key.dart';
import '../ui/palette.dart';

/// Layout usado enquanto o desktop não envia o seu (mensagem LAYOUT).
/// "mod" vira Cmd no macOS e Ctrl no Linux/Windows (resolvido no daemon).
final List<Layer> defaultLayers = [
  Layer(
    id: 'vscode',
    name: 'VS Code',
    color: Palette.blue,
    columns: 3,
    keys: [
      MacroKey(id: 'btn_palette', label: 'Palette', icon: 'search', action: MacroAction.combo(['mod', 'shift', 'p'])),
      MacroKey(id: 'btn_quickopen', label: 'Quick Open', icon: 'file', action: MacroAction.combo(['mod', 'p'])),
      MacroKey(id: 'btn_terminal', label: 'Terminal', icon: 'terminal', action: MacroAction.combo(['ctrl', '`'])),
      MacroKey(id: 'btn_comment', label: 'Comment', icon: 'comment', action: MacroAction.combo(['mod', '/'])),
      MacroKey(id: 'btn_format', label: 'Format', icon: 'format', action: MacroAction.combo(['shift', 'alt', 'f'])),
      MacroKey(id: 'btn_rename', label: 'Rename', icon: 'edit', action: MacroAction.combo(['f2'])),
      MacroKey(
        id: 'btn_log',
        label: 'console.log',
        icon: 'code',
        action: MacroAction.snippet(r"console.log('DEBUG:', $0);"),
      ),
      MacroKey(
        id: 'btn_trycatch',
        label: 'try/catch',
        icon: 'code',
        action: MacroAction.snippet('try {\n  \$0\n} catch (err) {\n  console.error(err);\n}'),
      ),
      MacroKey(id: 'btn_save_all', label: 'Salvar', icon: 'save', action: MacroAction.combo(['mod', 's'])),
    ],
  ),
  Layer(
    id: 'git',
    name: 'Git / Shell',
    color: Palette.green,
    columns: 3,
    keys: [
      MacroKey(id: 'btn_git_status', label: 'Status', icon: 'info', action: MacroAction.shell('git status --short')),
      MacroKey(id: 'btn_git_pull', label: 'Pull', icon: 'down', action: MacroAction.shell('git pull origin main')),
      MacroKey(id: 'btn_git_push', label: 'Push', icon: 'up', confirm: true, action: MacroAction.shell('git push')),
      MacroKey(
        id: 'btn_docker_build',
        label: 'Docker Build',
        icon: 'build',
        action: MacroAction.shell('docker compose build', timeoutSec: 900),
      ),
      MacroKey(
        id: 'btn_docker_up',
        label: 'Compose Up',
        icon: 'play',
        action: MacroAction.shell('docker compose up -d'),
      ),
      MacroKey(
        id: 'btn_docker_down',
        label: 'Compose Down',
        icon: 'stop',
        action: MacroAction.shell('docker compose down'),
      ),
      MacroKey(id: 'btn_npm_test', label: 'npm test', icon: 'check', action: MacroAction.shell('npm test')),
      MacroKey(id: 'btn_clear', label: 'Clear', icon: 'clear', action: MacroAction.combo(['ctrl', 'l'])),
      MacroKey(id: 'btn_interrupt', label: 'Ctrl+C', icon: 'stop', action: MacroAction.combo(['ctrl', 'c'])),
    ],
  ),
  Layer(
    id: 'debug',
    name: 'Navegação / Debug',
    color: Palette.yellow,
    columns: 4,
    keys: [
      MacroKey(id: 'btn_dbg_continue', label: 'Continue', icon: 'play', action: MacroAction.combo(['f5'])),
      MacroKey(id: 'btn_dbg_over', label: 'Step Over', icon: 'next', action: MacroAction.combo(['f10'])),
      MacroKey(id: 'btn_dbg_into', label: 'Step Into', icon: 'down', action: MacroAction.combo(['f11'])),
      MacroKey(id: 'btn_dbg_out', label: 'Step Out', icon: 'up', action: MacroAction.combo(['shift', 'f11'])),
      MacroKey(id: 'btn_dbg_bp', label: 'Breakpoint', icon: 'dot', action: MacroAction.combo(['f9'])),
      MacroKey(id: 'btn_dbg_stop', label: 'Stop', icon: 'stop', action: MacroAction.combo(['shift', 'f5'])),
      MacroKey(id: 'btn_nav_back', label: 'Back', icon: 'left', action: MacroAction.combo(['ctrl', '-'])),
      MacroKey(id: 'btn_nav_def', label: 'Go to Def', icon: 'right', action: MacroAction.combo(['f12'])),
      MacroKey(id: 'btn_tab_prev', label: 'Prev Tab', icon: 'left', action: MacroAction.combo(['ctrl', 'pageup'])),
      MacroKey(id: 'btn_tab_next', label: 'Next Tab', icon: 'right', action: MacroAction.combo(['ctrl', 'pagedown'])),
      MacroKey(id: 'btn_vol_down', label: 'Vol -', icon: 'voldown', action: MacroAction.combo(['volumedown'])),
      MacroKey(id: 'btn_vol_up', label: 'Vol +', icon: 'volup', action: MacroAction.combo(['volumeup'])),
    ],
  ),
];
