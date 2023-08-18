import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:whatsapp_clone/features/chat/controllers/chat_controller.dart';
import 'package:whatsapp_clone/features/chat/views/attachment_sender.dart';
import 'package:whatsapp_clone/theme/theme.dart';

final galleryStateProvider =
    AutoDisposeStateNotifierProvider<GalleryStateController, GalleryState>(
  (ref) => GalleryStateController(),
);

class GalleryState {
  final String title;
  final bool showSelectBtn;
  final bool canSelect;
  final List<AssetWrapper> selectedAssets;

  GalleryState({
    required this.title,
    required this.selectedAssets,
    required this.canSelect,
    required this.showSelectBtn,
  });

  GalleryState copyWith({
    String? title,
    List<AssetWrapper>? selectedAssets,
    bool? showSelectBtn,
    bool? canSelect,
  }) {
    return GalleryState(
      title: title ?? this.title,
      selectedAssets: selectedAssets ?? this.selectedAssets,
      showSelectBtn: showSelectBtn ?? this.showSelectBtn,
      canSelect: canSelect ?? this.canSelect,
    );
  }
}

class GalleryStateController extends StateNotifier<GalleryState> {
  GalleryStateController()
      : super(
          GalleryState(
            title: 'Send to Suhaib',
            selectedAssets: [],
            showSelectBtn: false,
            canSelect: false,
          ),
        );

  late final bool shouldReturnFiles;

  void init({required bool returnFiles}) {
    shouldReturnFiles = returnFiles;
  }

  void setSelectBtnVisibility(bool val) {
    state = state.copyWith(showSelectBtn: val);
  }

  void toggleCanSelect() {
    state = state.copyWith(
      canSelect: !state.canSelect,
      selectedAssets: state.canSelect == true ? [] : null,
    );
  }

  void selectAsset(AssetWrapper asset) {
    state = state.copyWith(selectedAssets: [
      ...state.selectedAssets,
      asset,
    ]);
  }

  void unselectAsset(AssetWrapper asset) {
    state = state.copyWith(
        selectedAssets: [...state.selectedAssets.where((id) => id != asset)]);
  }

  Future<void> prepareAttachments(
    BuildContext context,
    WidgetRef ref,
    List<AssetWrapper> selectedAssets,
  ) async {
    final files = await Future.wait(
      selectedAssets.map(
        (e) => e.asset.file.then((value) => value!),
      ),
    );

    final attachments = await ref
        .read(chatControllerProvider.notifier)
        .createAttachmentsFromFiles(files);

    if (!mounted) return;
    if (shouldReturnFiles) {
      Navigator.popUntil(
        context,
        (route) => route.settings.name == "/gallery",
      );
      Navigator.pop(context, files.first);
      return;
    }

    final returnedAttachments = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AttachmentMessageSender(
          attachments: List.from(attachments),
          tags: selectedAssets.map((e) => e.asset.id).toList(),
        ),
      ),
    );

    if (returnedAttachments == null) return;
    final newSelectedAssets = <AssetWrapper>[];

    for (var i = 0; i < attachments.length; i++) {
      if (returnedAttachments.contains(attachments[i])) {
        newSelectedAssets.add(selectedAssets[i]);
      }
    }

    state = state.copyWith(
      selectedAssets: newSelectedAssets,
      showSelectBtn: newSelectedAssets.isEmpty ? state.showSelectBtn : false,
      canSelect: newSelectedAssets.isEmpty ? state.canSelect : true,
    );
  }
}

class AssetData {
  const AssetData({required this.assets, required this.albums});

  final Map<String, AssetWrapper> assets;
  final Map<String, List<String>> albums;
}

class AssetWrapper {
  const AssetWrapper({required this.asset, required this.thumbnail});

  final AssetEntity asset;
  final Uint8List thumbnail;
}

class Gallery extends ConsumerStatefulWidget {
  const Gallery({super.key, required this.title, this.returnFiles = false});

  final String title;
  final bool returnFiles;

  @override
  ConsumerState<Gallery> createState() => _GalleryState();
}

class _GalleryState extends ConsumerState<Gallery>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Stream<AssetData> _albumsFuture;

  @override
  void initState() {
    _albumsFuture = loadAssets();
    ref
        .read(galleryStateProvider.notifier)
        .init(returnFiles: widget.returnFiles);

    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 1,
    )..addListener(_tabListener);

    super.initState();
  }

  Stream<AssetData> loadAssets() async* {
    final albumList = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: widget.returnFiles ? RequestType.image : RequestType.common,
    );
    final allAssets = await albumList.first.getAssetListRange(
      start: 0,
      end: 999999,
    );

    final Map<String, AssetWrapper> assets = {};
    final Map<String, List<String>> albums = {'Recents': []};
    final List<Future> futures = [];

    for (final asset in allAssets) {
      final thumbnail = await asset.thumbnailDataWithSize(
        const ThumbnailSize.square(300),
        quality: 100,
      );
      assets[asset.id] = AssetWrapper(asset: asset, thumbnail: thumbnail!);

      final key = asset.relativePath!
          .substring(0, asset.relativePath!.length - 1)
          .split("/")
          .last;

      if (albums[key] == null) {
        albums[key] = [];
        yield AssetData(assets: assets, albums: albums);
      }

      albums[key]!.add(asset.id);
      albums['Recents']!.add(asset.id);
    }

    await Future.wait(futures);
  }

  void _tabListener() {
    if (widget.returnFiles) return;

    ref
        .read(galleryStateProvider.notifier)
        .setSelectBtnVisibility(_tabController.index == 0 ? true : false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_tabListener);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = Theme.of(context).custom.colorTheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: StatefulBuilder(
            builder: (context, _) {
              final canSelect = ref.watch(galleryStateProvider).canSelect;
              final selectedCount =
                  ref.read(galleryStateProvider).selectedAssets.length;
              final showSelectBtn =
                  ref.watch(galleryStateProvider).showSelectBtn &&
                      !widget.returnFiles;

              return AppBar(
                backgroundColor: colorTheme.backgroundColor,
                leading: IconButton(
                  onPressed: () {
                    if (canSelect) {
                      ref.read(galleryStateProvider.notifier).toggleCanSelect();
                      return;
                    }

                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Text(
                  canSelect
                      ? selectedCount == 0
                          ? 'Tap a photo to select'
                          : '$selectedCount selected'
                      : widget.title,
                ),
                actions: [
                  if (!canSelect && showSelectBtn)
                    IconButton(
                      onPressed: ref
                          .read(galleryStateProvider.notifier)
                          .toggleCanSelect,
                      icon: const Icon(Icons.check_box_outlined),
                    )
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(50),
                  child: Container(
                    color: colorTheme.appBarColor,
                    child: TabBar(
                      controller: _tabController,
                      physics: const BouncingScrollPhysics(),
                      tabs: const [
                        Tab(text: 'Recents'),
                        Tab(text: 'Albums'),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        body: StreamBuilder(
          stream: _albumsFuture,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Container();
            }

            return TabBarView(
              controller: _tabController,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: AlbumView(
                    showAlbumName: false,
                    assets: snap.data!.assets.values.toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: AlbumsTab(assetData: snap.data!),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AlbumsTab extends StatelessWidget {
  const AlbumsTab({super.key, required this.assetData});
  final AssetData assetData;

  @override
  Widget build(BuildContext context) {
    final albumTitles = assetData.albums.keys.toList();

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: albumTitles.length,
      itemBuilder: (context, index) {
        final albumTitle = albumTitles[index];
        final assets = assetData.albums[albumTitle]!
            .map((assetId) => assetData.assets[assetId]!)
            .toList();

        return AlbumCard(albumTitle: albumTitle, assets: assets);
      },
    );
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.albumTitle,
    required this.assets,
  });

  final String albumTitle;
  final List<AssetWrapper> assets;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AlbumView(
              albumTitle: albumTitle,
              assets: assets,
            ),
          ),
        );
      },
      child: Stack(
        children: [
          FadeInThumbnail(thumbnail: assets.first.thumbnail),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 8.0,
              ),
              child: Container(
                decoration: const BoxDecoration(boxShadow: [
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 50,
                    spreadRadius: 5,
                  )
                ]),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(
                      Icons.folder,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      albumTitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    Text(assets.length.toString())
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AlbumView extends ConsumerStatefulWidget {
  const AlbumView({
    super.key,
    this.albumTitle,
    this.showAlbumName = true,
    required this.assets,
  });

  final String? albumTitle;
  final bool showAlbumName;
  final List<AssetWrapper> assets;

  @override
  ConsumerState<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends ConsumerState<AlbumView> {
  @override
  Widget build(BuildContext context) {
    final selectedAssets = ref.watch(galleryStateProvider).selectedAssets;
    final showSelectedAssets = selectedAssets.isNotEmpty;
    final canSelect = ref.watch(galleryStateProvider).canSelect;
    final colorTheme = Theme.of(context).custom.colorTheme;

    return Scaffold(
      appBar: !widget.showAlbumName
          ? null
          : AppBar(
              backgroundColor: colorTheme.backgroundColor,
              leading: IconButton(
                onPressed: () {
                  if (canSelect) {
                    ref.read(galleryStateProvider.notifier).toggleCanSelect();
                    return;
                  }

                  Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back),
              ),
              title: Text(
                canSelect
                    ? selectedAssets.isEmpty
                        ? 'Tap a photo to select'
                        : "${selectedAssets.length} selected"
                    : widget.albumTitle ?? '',
              ),
              actions: [
                if (!canSelect &&
                    !ref.read(galleryStateProvider.notifier).shouldReturnFiles)
                  IconButton(
                    onPressed:
                        ref.read(galleryStateProvider.notifier).toggleCanSelect,
                    icon: const Icon(Icons.check_box_outlined),
                  )
              ],
            ),
      backgroundColor: colorTheme.backgroundColor,
      body: WillPopScope(
        onWillPop: () async {
          if (canSelect) {
            ref.read(galleryStateProvider.notifier).toggleCanSelect();
            return false;
          }

          return true;
        },
        child: SafeArea(
          child: Stack(
            children: [
              GridView.builder(
                physics: const BouncingScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: widget.assets.length,
                itemBuilder: (context, index) {
                  return AlbumItem(
                    assetWrapper: widget.assets[index],
                  );
                },
              ),
              if (showSelectedAssets)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    color: Theme.of(context).custom.colorTheme.appBarColor,
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            scrollDirection: Axis.horizontal,
                            itemCount: selectedAssets.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 10.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Image.memory(
                                      selectedAssets[index].thumbnail,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        InkWell(
                          onTap: () => ref
                              .read(galleryStateProvider.notifier)
                              .prepareAttachments(
                                context,
                                ref,
                                selectedAssets,
                              ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                Theme.of(context).custom.colorTheme.greenColor,
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}

class AlbumItem extends ConsumerWidget {
  const AlbumItem({
    super.key,
    required this.assetWrapper,
  });

  final AssetWrapper assetWrapper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(galleryStateProvider).selectedAssets;
    final isSelected = selected
        .where(
          (element) => element.asset.id == assetWrapper.asset.id,
        )
        .isNotEmpty;

    return InkWell(
      onTap: () {
        if (!ref.read(galleryStateProvider).canSelect) {
          ref
              .read(galleryStateProvider.notifier)
              .prepareAttachments(context, ref, [assetWrapper]);
          return;
        }

        if (isSelected) {
          ref.read(galleryStateProvider.notifier).unselectAsset(assetWrapper);
          return;
        }

        ref.read(galleryStateProvider.notifier).selectAsset(assetWrapper);
      },
      child: Stack(
        children: [
          FadeInThumbnail(
            thumbnail: assetWrapper.thumbnail,
            heroTag: assetWrapper.asset.id,
          ),
          if (isSelected) ...[
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black12,
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 32,
              ),
            )
          ],
        ],
      ),
    );
  }
}

class FadeInThumbnail extends StatefulWidget {
  const FadeInThumbnail({
    super.key,
    required this.thumbnail,
    this.heroTag,
  });

  final Uint8List thumbnail;
  final String? heroTag;

  @override
  State<FadeInThumbnail> createState() => _FadeInThumbnailState();
}

class _FadeInThumbnailState extends State<FadeInThumbnail>
    with AutomaticKeepAliveClientMixin {
  double opacity = 0;

  @override
  void initState() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {
        opacity = 1;
      });
    });

    super.initState();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final image = Image.memory(
      widget.thumbnail,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );

    return Container(
      color: Theme.of(context).custom.colorTheme.appBarColor,
      width: 200,
      height: 200,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 300),
        child: widget.heroTag != null
            ? Hero(
                tag: widget.heroTag!,
                child: image,
              )
            : image,
      ),
    );
  }
}
