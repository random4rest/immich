<script lang="ts">
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import AssetRotateConfirmModal from '$lib/modals/AssetRotateConfirmModal.svelte';
  import { waitForWebsocketEvent } from '$lib/stores/websocket';
  import { handleError } from '$lib/utils/handle-error';
  import {
    AssetEditAction,
    editAsset,
    getAssetEdits,
    removeAssetEdits,
    type AssetEditActionItemDto,
    type RotateParameters,
  } from '@immich/sdk';
  import { modalManager, toastManager } from '@immich/ui';
  import { mdiRotateLeft, mdiRotateRight } from '@mdi/js';

  type Direction = 'cw' | 'ccw';

  type RotatedUpdate = {
    id: string;
    thumbhash: string | null;
    editVersion: string;
  };

  type Props = {
    onRotate?: (updates: RotatedUpdate[]) => void;
  };

  let { onRotate }: Props = $props();

  // Generous timeout to cover slow regen on large RAW images.
  const ROTATE_EVENT_TIMEOUT_MS = 30_000;

  const rotateOne = async (id: string, deltaDegrees: number): Promise<RotatedUpdate> => {
    const { edits } = await getAssetEdits({ id });

    // Preserve crop (must come first per server validation) + any mirror edits.
    const cropEdit = edits.find((e) => e.action === AssetEditAction.Crop);
    const mirrorEdits = edits.filter((e) => e.action === AssetEditAction.Mirror);
    const currentAngle =
      (edits.find((e) => e.action === AssetEditAction.Rotate)?.parameters as RotateParameters | undefined)?.angle ?? 0;
    const newAngle = (((currentAngle + deltaDegrees) % 360) + 360) % 360;

    const nextEdits: AssetEditActionItemDto[] = [
      ...(cropEdit ? [{ action: AssetEditAction.Crop, parameters: cropEdit.parameters }] : []),
      ...mirrorEdits.map((m) => ({ action: AssetEditAction.Mirror, parameters: m.parameters })),
      ...(newAngle === 0 ? [] : [{ action: AssetEditAction.Rotate, parameters: { angle: newAngle } }]),
    ];

    // Subscribe BEFORE issuing the request so we don't race the server-side job.
    const editReady = waitForWebsocketEvent(
      'AssetEditReadyV1',
      (event) => event.asset.id === id,
      ROTATE_EVENT_TIMEOUT_MS,
    );

    if (nextEdits.length === 0) {
      await removeAssetEdits({ id });
    } else {
      await editAsset({ id, assetEditsCreateDto: { edits: nextEdits } });
    }

    const [event] = await editReady;
    const maxSequence = event.edit.reduce((m, e) => Math.max(m, e.sequence), 0);
    return {
      id: event.asset.id,
      thumbhash: event.asset.thumbhash,
      editVersion: maxSequence > 0 ? String(maxSequence) : `cleared-${Date.now()}`,
    };
  };

  const handleRotate = async (direction: Direction) => {
    // The server only allows editing still images. Pre-filter live photos / videos.
    const eligible = assetMultiSelectManager.ownedAssets.filter(
      (asset) => asset.isImage && !asset.livePhotoVideoId,
    );
    if (eligible.length === 0) {
      toastManager.warning('No eligible images selected (videos and live photos cannot be rotated).');
      return;
    }

    const confirmed = await modalManager.show(AssetRotateConfirmModal, {
      size: eligible.length,
      direction,
    });
    if (!confirmed) {
      return;
    }

    const deltaDegrees = direction === 'cw' ? 90 : 270;

    try {
      const results = await Promise.allSettled(eligible.map((asset) => rotateOne(asset.id, deltaDegrees)));

      const succeeded: RotatedUpdate[] = [];
      let failedCount = 0;
      for (const [index, result] of results.entries()) {
        if (result.status === 'fulfilled') {
          succeeded.push(result.value);
          // Invalidate the asset detail cache so the viewer shows the rotated preview.
          eventManager.emit('AssetEditsApplied', result.value.id);
        } else {
          failedCount++;
          console.error(`[RotateAction] failed for asset ${eligible[index].id}`, result.reason);
        }
      }

      if (succeeded.length > 0) {
        onRotate?.(succeeded);
        toastManager.primary(
          direction === 'cw'
            ? `Rotated ${succeeded.length} ${succeeded.length === 1 ? 'image' : 'images'} 90° clockwise`
            : `Rotated ${succeeded.length} ${succeeded.length === 1 ? 'image' : 'images'} 90° counter-clockwise`,
        );
      }
      if (failedCount > 0) {
        toastManager.warning(`${failedCount} ${failedCount === 1 ? 'image' : 'images'} could not be rotated.`);
      }
      assetMultiSelectManager.clear();
    } catch (error) {
      handleError(error, 'Unable to rotate the selected images');
    }
  };
</script>

<ButtonContextMenu icon={mdiRotateRight} title="Rotate">
  <MenuOption text="Rotate 90° clockwise" icon={mdiRotateRight} onClick={() => handleRotate('cw')} />
  <MenuOption text="Rotate 90° counter-clockwise" icon={mdiRotateLeft} onClick={() => handleRotate('ccw')} />
</ButtonContextMenu>
