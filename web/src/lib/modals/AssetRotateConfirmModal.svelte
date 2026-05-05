<script lang="ts">
  import { ConfirmModal } from '@immich/ui';
  import { mdiRotateLeft, mdiRotateRight } from '@mdi/js';
  import { t } from 'svelte-i18n';

  type Props = {
    size: number;
    direction: 'cw' | 'ccw';
    onClose: (confirmed?: boolean) => void;
  };

  let { size, direction, onClose: onCloseParent }: Props = $props();

  const icon = $derived(direction === 'cw' ? mdiRotateRight : mdiRotateLeft);
  const title = $derived(
    direction === 'cw'
      ? `Rotate ${size} ${size === 1 ? 'image' : 'images'} 90° clockwise?`
      : `Rotate ${size} ${size === 1 ? 'image' : 'images'} 90° counter-clockwise?`,
  );

  const onClose = (confirmed?: boolean) => {
    onCloseParent(confirmed);
  };
</script>

<ConfirmModal {title} confirmText={$t('confirm')} {icon} {onClose}>
  {#snippet prompt()}
    <p>This will update the orientation of the selected images and regenerate their thumbnails.</p>
  {/snippet}
</ConfirmModal>
