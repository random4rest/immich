<script lang="ts">
  import { isDefined } from '$lib';
  import { clickOutside } from '$lib/actions/click-outside';
  import { listNavigation } from '$lib/actions/list-navigation';
  import CoordinatesInput from '$lib/components/shared-components/coordinates-input.svelte';
  import type Map from '$lib/components/shared-components/map/map.svelte';
  import { timeDebounceOnSearch, timeToLoadTheMap } from '$lib/constants';
  import SearchBar from '$lib/elements/SearchBar.svelte';
  import { geolocationManager } from '$lib/managers/geolocation.manager.svelte';
  import type { LatLng } from '$lib/types';
  import { delay } from '$lib/utils/asset-utils';
  import { handleError } from '$lib/utils/handle-error';
  import { searchNominatim, type NominatimPlace } from '$lib/utils/nominatim';
  import { searchPlaces, type AssetResponseDto, type PlacesResponseDto } from '@immich/sdk';
  import { ConfirmModal, LoadingSpinner } from '@immich/ui';
  import { mdiMapMarkerMultipleOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';

  type Props = {
    asset?: AssetResponseDto;
    point?: LatLng;
    onClose: (point?: LatLng) => void;
  };

  let { asset, point: initialPoint, onClose }: Props = $props();

  let places: PlacesResponseDto[] = $state([]);
  let suggestedPlaces: PlacesResponseDto[] = $derived(places.slice(0, 5));
  let nominatimPlaces: NominatimPlace[] = $state([]);
  let searchWord: string = $state('');
  let latestSearchTimeout: number;
  let nominatimAbort: AbortController | undefined;
  let showLoadingSpinner = $state(false);
  let suggestionContainer: HTMLDivElement | undefined = $state();
  let hideSuggestion = $state(false);
  let mapElement = $state<ReturnType<typeof Map>>();
  let hasAnySuggestion = $derived(suggestedPlaces.length > 0 || nominatimPlaces.length > 0);

  let assetPoint = $derived.by<LatLng | undefined>(() => {
    if (!asset || !asset.exifInfo) {
      return;
    }

    const { latitude, longitude } = asset.exifInfo;
    if (!isDefined(latitude) || !isDefined(longitude)) {
      return;
    }

    return { lat: latitude, lng: longitude };
  });

  let point = $state<LatLng | undefined>(initialPoint ?? assetPoint);
  let zoom = $state(point ? 12.5 : 1);
  let center = $state(point ?? geolocationManager.lastPoint);

  $effect(() => {
    if (mapElement && initialPoint) {
      mapElement.addClipMapMarker(initialPoint.lng, initialPoint.lat);
    }
  });

  $effect(() => {
    if (searchWord === '') {
      suggestedPlaces = [];
      nominatimPlaces = [];
    }
  });

  const handleConfirm = (confirmed?: boolean) => {
    if (point && confirmed) {
      geolocationManager.onSelected(point);
      onClose(point);
    } else {
      onClose();
    }
  };

  const getLocation = (name: string, admin1Name?: string, admin2Name?: string): string => {
    return `${name}${admin1Name ? ', ' + admin1Name : ''}${admin2Name ? ', ' + admin2Name : ''}`;
  };

  const handleSearchPlaces = () => {
    if (latestSearchTimeout) {
      clearTimeout(latestSearchTimeout);
    }
    showLoadingSpinner = true;

    // eslint-disable-next-line unicorn/prefer-global-this
    const searchTimeout = window.setTimeout(() => {
      if (searchWord === '') {
        places = [];
        nominatimPlaces = [];
        showLoadingSpinner = false;
        return;
      }

      // Try to parse coordinate pair from search input in the format `LATITUDE, LONGITUDE` as floats
      const coordinateParts = searchWord.split(',').map((part) => part.trim());
      if (coordinateParts.length === 2) {
        const coordinateLat = Number.parseFloat(coordinateParts[0]);
        const coordinateLng = Number.parseFloat(coordinateParts[1]);

        if (
          !Number.isNaN(coordinateLat) &&
          !Number.isNaN(coordinateLng) &&
          coordinateLat >= -90 &&
          coordinateLat <= 90 &&
          coordinateLng >= -180 &&
          coordinateLng <= 180
        ) {
          places = [];
          nominatimPlaces = [];
          showLoadingSpinner = false;
          handleUseSuggested(coordinateLat, coordinateLng);
          return;
        }
      }

      // Fire local DB search and Nominatim search in parallel; both render together.
      const localSearch = searchPlaces({ name: searchWord })
        .then((searchResult) => {
          if (latestSearchTimeout === searchTimeout) {
            places = searchResult;
          }
        })
        .catch((error) => {
          if (latestSearchTimeout === searchTimeout) {
            places = [];
            handleError(error, $t('errors.cant_search_places'));
          }
        });

      // Cancel any in-flight Nominatim request from earlier keystrokes.
      nominatimAbort?.abort();
      nominatimAbort = new AbortController();
      const nominatimSearch = searchNominatim(searchWord, nominatimAbort.signal)
        .then((result) => {
          if (latestSearchTimeout === searchTimeout) {
            nominatimPlaces = result;
          }
        })
        .catch((error) => {
          if (error?.name === 'AbortError') {
            return;
          }
          if (latestSearchTimeout === searchTimeout) {
            nominatimPlaces = [];
            console.warn('[GeolocationPointPicker] Nominatim search failed', error);
          }
        });

      Promise.all([localSearch, nominatimSearch]).finally(() => {
        if (latestSearchTimeout === searchTimeout) {
          showLoadingSpinner = false;
        }
      });
    }, timeDebounceOnSearch);
    latestSearchTimeout = searchTimeout;
  };

  const handleUseSuggested = (latitude: number, longitude: number) => {
    hideSuggestion = true;
    point = { lng: longitude, lat: latitude };
    mapElement?.addClipMapMarker(longitude, latitude);
  };

  const onUpdate = (lat: number, lng: number) => {
    point = { lat, lng };
    mapElement?.addClipMapMarker(lng, lat);
  };
</script>

<ConfirmModal
  confirmColor="primary"
  title={$t('change_location')}
  icon={mdiMapMarkerMultipleOutline}
  size="medium"
  onClose={handleConfirm}
>
  {#snippet prompt()}
    <div class="flex flex-col w-full h-full gap-2">
      <div class="relative w-64 sm:w-96 z-1">
        {#if suggestionContainer}
          <div use:listNavigation={suggestionContainer}>
            <button type="button" class="w-full" onclick={() => (hideSuggestion = false)}>
              <SearchBar
                placeholder={$t('search_places')}
                bind:name={searchWord}
                {showLoadingSpinner}
                onReset={() => {
                  suggestedPlaces = [];
                  nominatimPlaces = [];
                }}
                onSearch={handleSearchPlaces}
                roundedBottom={!hasAnySuggestion || hideSuggestion}
              />
            </button>
          </div>
        {/if}

        <div
          class="absolute w-full"
          id="suggestion"
          bind:this={suggestionContainer}
          use:clickOutside={{ onOutclick: () => (hideSuggestion = true) }}
        >
          {#if !hideSuggestion && hasAnySuggestion}
            {#each suggestedPlaces as place, index (place.latitude + place.longitude)}
              <button
                type="button"
                class="flex w-full border-t border-gray-400 dark:border-immich-dark-gray h-14 place-items-center bg-gray-200 p-2 dark:bg-gray-700 hover:bg-gray-300 hover:dark:bg-[#232932] focus:bg-gray-300 focus:dark:bg-[#232932] {nominatimPlaces.length ===
                  0 && index === suggestedPlaces.length - 1
                  ? 'rounded-b-lg border-b'
                  : ''}"
                onclick={() => handleUseSuggested(place.latitude, place.longitude)}
              >
                <p class="ms-4 text-sm text-gray-700 dark:text-gray-100 truncate">
                  {getLocation(place.name, place.admin1name, place.admin2name)}
                </p>
              </button>
            {/each}

            {#if nominatimPlaces.length > 0}
              <div
                class="flex w-full border-t border-gray-400 dark:border-immich-dark-gray bg-gray-100 dark:bg-gray-800 p-2 ps-6"
              >
                <span class="text-xs uppercase tracking-wide text-gray-600 dark:text-gray-400">
                  Points of interest (OpenStreetMap)
                </span>
              </div>
              {#each nominatimPlaces as place, index (`osm-${place.lat}-${place.lng}-${index}`)}
                <button
                  type="button"
                  class="flex w-full border-t border-gray-400 dark:border-immich-dark-gray h-14 place-items-center bg-gray-200 p-2 dark:bg-gray-700 hover:bg-gray-300 hover:dark:bg-[#232932] focus:bg-gray-300 focus:dark:bg-[#232932] {index ===
                  nominatimPlaces.length - 1
                    ? 'rounded-b-lg border-b'
                    : ''}"
                  onclick={() => handleUseSuggested(place.lat, place.lng)}
                  title={place.displayName}
                >
                  <div class="ms-4 flex flex-col items-start min-w-0">
                    <p class="text-sm text-gray-700 dark:text-gray-100 truncate w-full text-start">
                      {place.name}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-gray-400 truncate w-full text-start">
                      {place.displayName}
                    </p>
                  </div>
                </button>
              {/each}
            {/if}
          {/if}
        </div>
      </div>

      <span>{$t('pick_a_location')}</span>
      <div class="h-125 min-h-75 w-full z-0">
        {#await import('$lib/components/shared-components/map/map.svelte')}
          {#await delay(timeToLoadTheMap) then}
            <!-- show the loading spinner only if loading the map takes too much time -->
            <div class="flex items-center justify-center h-full w-full">
              <LoadingSpinner />
            </div>
          {/await}
        {:then { default: Map }}
          <Map
            bind:this={mapElement}
            mapMarkers={asset && assetPoint
              ? [
                  {
                    id: asset.id,
                    lat: assetPoint.lat,
                    lon: assetPoint.lng,
                    city: asset.exifInfo?.city ?? null,
                    state: asset.exifInfo?.state ?? null,
                    country: asset.exifInfo?.country ?? null,
                  },
                ]
              : []}
            {zoom}
            {center}
            simplified={true}
            clickable={true}
            onClickPoint={(selected) => (point = selected)}
            showSettings={false}
            rounded
          />
        {/await}
      </div>

      <div class="grid sm:grid-cols-2 gap-4 text-sm text-start mt-4">
        <CoordinatesInput lat={point?.lat} lng={point?.lng} {onUpdate} />
      </div>
    </div>
  {/snippet}
</ConfirmModal>
