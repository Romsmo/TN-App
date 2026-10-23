// The few things that differ between a device and the browser preview used for development:
// where files live and which library backend is used. On a device (`dart.library.io`) the real client library is
// loaded; in the browser preview a clearly marked demo backend answers instead.
export 'platform_web.dart' if (dart.library.io) 'platform_io.dart';
