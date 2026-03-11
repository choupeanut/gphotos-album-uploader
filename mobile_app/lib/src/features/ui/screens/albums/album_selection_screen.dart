import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class AlbumSelectionScreen extends StatefulWidget {
  final List<AssetPathEntity> albums;
  final Map<String, Map<String, int>> stats;

  const AlbumSelectionScreen({super.key, required this.albums, required this.stats});

  @override
  State<AlbumSelectionScreen> createState() => _AlbumSelectionScreenState();
}

class _AlbumSelectionScreenState extends State<AlbumSelectionScreen> {
  final Set<AssetPathEntity> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('選擇要備份的相簿', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_selected.toList()),
              child: Text(
                '確認 (${_selected.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: widget.albums.length,
        itemBuilder: (context, index) {
          final album = widget.albums[index];
          final isSelected = _selected.contains(album);

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selected.remove(album);
                } else {
                  _selected.add(album);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Album Cover Image
                    FutureBuilder<List<AssetEntity>>(
                      // Just get the first image for the thumbnail
                      future: album.getAssetListRange(start: 0, end: 1),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                        }
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          final asset = snapshot.data!.first;
                          return AssetEntityImage(
                            asset,
                            isOriginal: false,
                            thumbnailSize: const ThumbnailSize.square(250),
                            fit: BoxFit.cover,
                          );
                        }
                        return Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.photo_album, size: 50, color: Colors.grey),
                        );
                      },
                    ),

                    // Gradient overlay for text readability
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Album Name and Count
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: FutureBuilder<int>(
                        future: album.assetCountAsync,
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          
                          // Check if this album is in the stats and is fully uploaded
                          final albumStats = widget.stats[album.name];
                          bool isFullyUploaded = false;
                          if (albumStats != null) {
                            final total = albumStats['total'] ?? 0;
                            final done = albumStats['done'] ?? 0;
                            // 如果資料庫中該相簿的總數大於 0，且等於完成數量，而且跟手機目前的數量差不多，我們就視為已備份
                            if (total > 0 && done == total && done >= count) {
                              isFullyUploaded = true;
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      album.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isFullyUploaded)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4.0),
                                      child: Icon(Icons.cloud_done, color: Colors.white, size: 14),
                                    ),
                                ],
                              ),
                              Text(
                                '$count 項',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Checkmark indicator
                    if (isSelected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, size: 20, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
