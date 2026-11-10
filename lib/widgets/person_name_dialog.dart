import 'package:flutter/material.dart';

import 'text_prompt_dialog.dart';

/// Asks for a person's name. [validate] returns an error message or null.
Future<String?> showPersonNameDialog(
  BuildContext context, {
  required String? Function(String) validate,
  String title = 'Add person',
  String initial = '',
}) =>
    showTextPromptDialog(
      context,
      title: title,
      label: 'Name',
      initial: initial,
      validate: validate,
      fieldKey: 'personName',
      capitalization: TextCapitalization.words,
    );
