import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// True if [e] means "the server could not be reached" (offline, DNS,
/// timeout) – as opposed to the server answering with an error.
/// Only these errors are safe to retry later; a server error such as
/// "RLS policy violated" would fail again, so it must not be queued.
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is HttpException ||
    e is http.ClientException ||
    e is TimeoutException ||
    e is HandshakeException ||
    (e is AuthRetryableFetchException && e.statusCode == null);
