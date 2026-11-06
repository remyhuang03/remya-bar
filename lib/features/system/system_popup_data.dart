import 'system_backend.dart';

Map<String, Object?> mediaPopupData(
  List<MediaPlayerSnapshot> players, {
  String? error,
}) => {
  'error': error,
  'players': [
    for (final player in players)
      {
        'name': player.busName,
        'identity': player.identity,
        'title': player.title,
        'artist': player.artist,
        'album': player.album,
        'artUrl': player.artUrl,
        'status': player.playbackStatus,
        'canPlayPause':
            player.canControl &&
            (player.playbackStatus == 'Playing'
                ? player.canPause
                : player.canPlay),
        'canPrevious': player.canControl && player.canGoPrevious,
        'canNext': player.canControl && player.canGoNext,
        'seekToken': player.seekToken,
        'positionSeconds': player.positionSeconds,
        'lengthSeconds': player.lengthSeconds,
      },
  ],
};
