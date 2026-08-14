import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uses TetoTV's remote keyboard or the Android device keyboard according to
/// the saved input preference.
class TvTextInput extends ConsumerStatefulWidget {
  const TvTextInput({
    required this.controller,
    required this.labelText,
    this.hintText,
    this.keyboardTitle,
    this.focusNode,
    this.autofocus = false,
    this.obscureText = false,
    this.autofillSuggestions = const [],
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final String? keyboardTitle;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscureText;
  final List<String> autofillSuggestions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  ConsumerState<TvTextInput> createState() => _TvTextInputState();
}

class _TvTextInputState extends ConsumerState<TvTextInput> {
  FocusNode? _fallbackFocusNode;
  bool _deviceKeyboardActive = false;

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _fallbackFocusNode = FocusNode(debugLabel: 'TV text input');
    }
    _focusNode.addListener(_handleFocusChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant TvTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _fallbackFocusNode)?.removeListener(
        _handleFocusChanged,
      );
      _fallbackFocusNode?.dispose();
      _fallbackFocusNode = widget.focusNode == null
          ? FocusNode(debugLabel: 'TV text input')
          : null;
      _focusNode.addListener(_handleFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _fallbackFocusNode?.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus || !_deviceKeyboardActive) return;
    setState(() => _deviceKeyboardActive = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _activateDeviceKeyboard() {
    if (_deviceKeyboardActive) return;
    setState(() => _deviceKeyboardActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _finishDeviceKeyboard(String value) {
    widget.onSubmitted?.call(value);
    if (_deviceKeyboardActive) {
      setState(() => _deviceKeyboardActive = false);
    }
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _focusNode.requestFocus();
  }

  KeyEventResult _handleDeviceActivation(FocusNode _, KeyEvent event) {
    if (_deviceKeyboardActive || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _activateDeviceKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openKeyboard(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .20),
      builder: (_) => TvKeyboardDialog(
        title: widget.keyboardTitle ?? widget.labelText,
        initialValue: widget.controller.text,
        obscureText: widget.obscureText,
        autofillSuggestions: widget.autofillSuggestions,
      ),
    );
    if (value == null || !context.mounted) return;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
    widget.onSubmitted?.call(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final useBuiltInKeyboard = ref.watch(
      settingsPreferencesProvider.select(
        (preferences) => preferences.useBuiltInKeyboard,
      ),
    );
    if (!useBuiltInKeyboard) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: _handleDeviceActivation,
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          readOnly: !_deviceKeyboardActive,
          showCursor: _deviceKeyboardActive,
          enableInteractiveSelection: _deviceKeyboardActive,
          obscureText: widget.obscureText,
          autocorrect: !widget.obscureText,
          enableSuggestions: !widget.obscureText,
          textInputAction: TextInputAction.done,
          onTap: _activateDeviceKeyboard,
          onChanged: widget.onChanged,
          onSubmitted: _finishDeviceKeyboard,
          style: TextStyle(color: context.appPalette.primaryText, fontSize: 15),
          cursorColor: context.appPalette.accentBright,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            labelStyle: TextStyle(color: context.appPalette.mutedText),
            hintStyle: TextStyle(color: context.appPalette.mutedText),
            filled: true,
            fillColor: context.appPalette.background.withValues(alpha: .82),
            suffixIcon: Icon(
              Icons.keyboard_alt_outlined,
              color: context.appPalette.secondaryAccent,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: .14),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: context.appPalette.accentBright,
                width: 2,
              ),
            ),
          ),
        ),
      );
    }
    final value = widget.controller.text;
    final visibleValue = widget.obscureText && value.isNotEmpty
        ? List.filled(value.length.clamp(1, 48), '\u2022').join()
        : value;
    return TvFocusable(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      focusScale: 1.015,
      borderRadius: BorderRadius.circular(8),
      onPressed: () => _openKeyboard(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.fromLTRB(13, 7, 10, 7),
        decoration: BoxDecoration(
          color: context.appPalette.background.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.labelText,
                    style: TextStyle(
                      color: context.appPalette.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    visibleValue.isEmpty
                        ? (widget.hintText ?? '')
                        : visibleValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visibleValue.isEmpty
                          ? context.appPalette.mutedText
                          : context.appPalette.primaryText,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.keyboard_rounded,
              color: context.appPalette.secondaryAccent,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class TvKeyboardDialog extends StatefulWidget {
  const TvKeyboardDialog({
    required this.title,
    required this.initialValue,
    this.obscureText = false,
    this.autofillSuggestions = const [],
    super.key,
  });

  final String title;
  final String initialValue;
  final bool obscureText;
  final List<String> autofillSuggestions;

  @override
  State<TvKeyboardDialog> createState() => _TvKeyboardDialogState();
}

class _TvKeyboardDialogState extends State<TvKeyboardDialog> {
  static const _letterRows = <List<String>>[
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.'],
  ];
  static const _symbolRows = <List<String>>[
    ['!', '@', '#', r'$', '%', '^', '&', '*', '(', ')'],
    ['-', '_', '=', '+', '[', ']', '{', '}', r'\', '|'],
    ['.', ',', ':', ';', '/', '?', '"', "'", '<', '>'],
  ];
  static const _numberRows = <List<String>>[
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
  ];

  late String _value;
  bool _shift = false;
  bool _symbols = false;
  late bool _reveal;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _reveal = !widget.obscureText;
  }

  void _append(String value) {
    setState(() {
      _value += _shift && !_symbols ? value.toUpperCase() : value;
      if (_shift) _shift = false;
    });
  }

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (value == null || value.isEmpty || !mounted) return;
    setState(() => _value += value.replaceAll(RegExp(r'[\r\n]+'), ''));
  }

  void _autofill(String value) {
    setState(() => _value = value);
  }

  KeyEventResult _handlePhysicalKeyboard(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      Navigator.of(context).pop(_value);
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 32) {
      setState(() => _value += character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final displayValue = !_reveal && _value.isNotEmpty
        ? List.filled(_value.length, '\u2022').join()
        : _value;
    final rows = _symbols ? _symbolRows : _letterRows;
    final availableWidth = MediaQuery.sizeOf(context).width;
    return Dialog(
      alignment: Alignment.bottomCenter,
      insetPadding: EdgeInsets.fromLTRB(
        availableWidth < 600 ? 10 : 24,
        availableWidth < 600 ? 48 : 160,
        availableWidth < 600 ? 10 : 24,
        18,
      ),
      backgroundColor: Colors.transparent,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handlePhysicalKeyboard,
        child: Container(
          key: const ValueKey('tv-keyboard-panel'),
          width: availableWidth < 600 ? availableWidth - 20 : 560,
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              palette.surface.withValues(alpha: .40),
              palette.background,
            ).withValues(alpha: 247 / 255),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.accent.withValues(alpha: .32)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x88000000),
                blurRadius: 22,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: palette.primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'REMOTE  /  CONTROLLER  /  KEYBOARD',
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: palette.accentBright.withValues(alpha: .62),
                  ),
                ),
                child: Text(
                  displayValue.isEmpty ? 'Start typing…' : displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: displayValue.isEmpty
                        ? palette.mutedText
                        : palette.primaryText,
                    fontSize: 12,
                    letterSpacing: widget.obscureText ? 1.4 : 0,
                  ),
                ),
              ),
              if (widget.autofillSuggestions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'AUTOFILL',
                      style: TextStyle(
                        color: palette.accentBright,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 7),
                    for (final suggestion in widget.autofillSuggestions.take(
                      3,
                    )) ...[
                      _AutofillChip(
                        label: suggestion,
                        icon: Icons.auto_awesome_rounded,
                        onPressed: () => _autofill(suggestion),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 5),
              FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          for (
                            var rowIndex = 0;
                            rowIndex < rows.length;
                            rowIndex++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                left: rowIndex == 1 ? 12 : 0,
                                right: rowIndex == 1 ? 12 : 0,
                                bottom: 3,
                              ),
                              child: Row(
                                children: [
                                  for (
                                    var keyIndex = 0;
                                    keyIndex < rows[rowIndex].length;
                                    keyIndex++
                                  ) ...[
                                    Expanded(
                                      child: _KeyboardKey(
                                        label: _shift && !_symbols
                                            ? rows[rowIndex][keyIndex]
                                                  .toUpperCase()
                                            : rows[rowIndex][keyIndex],
                                        autofocus:
                                            rowIndex == 0 && keyIndex == 0,
                                        onPressed: () =>
                                            _append(rows[rowIndex][keyIndex]),
                                      ),
                                    ),
                                    if (keyIndex != rows[rowIndex].length - 1)
                                      const SizedBox(width: 3),
                                  ],
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              _KeyboardAction(
                                label: _shift ? 'Aa ON' : 'Aa',
                                icon: Icons.arrow_upward_rounded,
                                selected: _shift,
                                onPressed: () => setState(() {
                                  if (_symbols) {
                                    _symbols = false;
                                    _shift = true;
                                  } else {
                                    _shift = !_shift;
                                  }
                                }),
                              ),
                              const SizedBox(width: 3),
                              _KeyboardAction(
                                label: _symbols ? 'ABC' : '#?&',
                                icon: Icons.alternate_email_rounded,
                                flex: 2,
                                selected: _symbols,
                                onPressed: () => setState(() {
                                  _symbols = !_symbols;
                                  _shift = false;
                                }),
                              ),
                              const SizedBox(width: 3),
                              _KeyboardAction(
                                label: 'SPACE',
                                icon: Icons.space_bar_rounded,
                                flex: 3,
                                onPressed: () => _append(' '),
                              ),
                              const SizedBox(width: 3),
                              _KeyboardAction(
                                label: 'DEL',
                                icon: Icons.backspace_outlined,
                                flex: 2,
                                onPressed: _backspace,
                              ),
                              const SizedBox(width: 3),
                              _KeyboardAction(
                                label: 'PASTE',
                                icon: Icons.content_paste_rounded,
                                flex: 2,
                                onPressed: _paste,
                              ),
                              if (widget.obscureText) ...[
                                const SizedBox(width: 3),
                                _KeyboardAction(
                                  label: _reveal ? 'HIDE' : 'SHOW',
                                  icon: _reveal
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  flex: 2,
                                  onPressed: () =>
                                      setState(() => _reveal = !_reveal),
                                ),
                              ],
                              const SizedBox(width: 3),
                              _KeyboardAction(
                                label: 'DONE',
                                icon: Icons.search_rounded,
                                flex: 2,
                                primary: true,
                                onPressed: () =>
                                    Navigator.of(context).pop(_value),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Column(
                        children: [
                          for (final numberRow in _numberRows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index < numberRow.length;
                                    index++
                                  ) ...[
                                    Expanded(
                                      child: _KeyboardKey(
                                        label: numberRow[index],
                                        onPressed: () =>
                                            _append(numberRow[index]),
                                      ),
                                    ),
                                    if (index != numberRow.length - 1)
                                      const SizedBox(width: 3),
                                  ],
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: _KeyboardKey(
                                  label: '0',
                                  onPressed: () => _append('0'),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: _KeyboardKey(
                                  label: 'CLEAR',
                                  compactLabel: true,
                                  onPressed: () => setState(() => _value = ''),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: _KeyboardKey(
                                  label: 'CANCEL',
                                  compactLabel: true,
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.compactLabel = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool compactLabel;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusScale: 1.04,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Container(
        height: 26,
        alignment: Alignment.center,
        color: context.appPalette.selectableSurface,
        child: Text(
          label,
          style: TextStyle(
            fontSize: compactLabel ? 6 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _KeyboardAction extends StatelessWidget {
  const _KeyboardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.flex = 1,
    this.primary = false,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final int flex;
  final bool primary;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: flex,
      child: TvFocusable(
        focusScale: 1.025,
        borderRadius: BorderRadius.circular(8),
        onPressed: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 46),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          color: primary
              ? context.appPalette.accent
              : selected
              ? context.appPalette.accent.withValues(alpha: .45)
              : context.appPalette.selectableSurface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutofillChip extends StatelessWidget {
  const _AutofillChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: TvFocusable(
        onPressed: onPressed,
        focusScale: 1.02,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          color: context.appPalette.selectableSurface,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: context.appPalette.accentBright),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
