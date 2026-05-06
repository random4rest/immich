<script lang="ts">
  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import AssetSelectionChangeDateModal from '$lib/modals/AssetSelectionChangeDateModal.svelte';
  import { fromTimelinePlainDateTime } from '$lib/utils/timeline-util';
  import { modalManager } from '@immich/ui';
  import { mdiCalendarEditOutline } from '@mdi/js';
  import { DateTime } from 'luxon';
  import { t } from 'svelte-i18n';

  type Props = {
    menuItem?: boolean;
  };

  let { menuItem = false }: Props = $props();

  const handleChangeDate = async () => {
    const assets = assetMultiSelectManager.ownedAssets;
    const initialDate = assets.length === 1 ? fromTimelinePlainDateTime(assets[0].localDateTime) : DateTime.now();
    await modalManager.show(AssetSelectionChangeDateModal, {
      initialDate,
      assets,
    });
    // [fork] selection intentionally preserved so the user can chain bulk edits
    // (e.g. change-date → change-location). Clear via Esc / X on the bar.
  };
</script>

{#if menuItem}
  <MenuOption text={$t('change_date')} icon={mdiCalendarEditOutline} onClick={handleChangeDate} />
{/if}
