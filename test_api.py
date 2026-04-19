import requests
import json
import base64
import hashlib
import logging
import sys
import re
from typing import List, Optional, Dict, Any
from urllib.parse import quote, unquote

# Setup logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler("api_test.log", mode='w', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class TestFailure(Exception):
    pass

def assert_not_empty(data, message):
    if not data:
        logger.error(f"Assertion Failed: {message}")
        raise TestFailure(message)
    logger.info(f"Check Passed: {message}")

# ════════════════════════════════════════════════════════════════════════════
# ANIME CORES
# ════════════════════════════════════════════════════════════════════════════

class HentaiVietsubTest:
    base_url = 'https://hentaivietsub.com'
    headers = {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    }

    @classmethod
    def run(cls):
        logger.info("--- Testing HentaiVietsub ---")
        # Trending
        res = requests.get(cls.base_url, headers=cls.headers, timeout=15)
        assert_not_empty(res.text, "HentaiVietsub Trending response")
        
        # Search
        search_url = f"{cls.base_url}/tim-kiem/overflow"
        res = requests.get(search_url, headers=cls.headers, timeout=15)
        assert_not_empty(res.text, "HentaiVietsub Search response")
        
        # Parse first item for stream test
        parts = re.split(r'class=["\']item-box["\'][^>]*>', res.text)
        assert_not_empty(len(parts) > 1, "HentaiVietsub Search results (split)")
        
        # Extract first link from the first item block
        block = parts[1]
        link_match = re.search(r'<a[^>]+href=["\']([^"\']+)["\']', block)
        assert_not_empty(link_match, "HentaiVietsub Item Link")
        link = link_match.group(1)
        if not link.startswith('http'): link = cls.base_url + link
        
        # Stream URL
        logger.info(f"Testing stream for: {link}")
        res = requests.get(link, headers=cls.headers, timeout=15)
        video_id_match = re.search(r'videos/([a-fA-F0-9]{24})', res.text)
        if video_id_match:
            video_id = video_id_match.group(1)
            config_url = f'https://p1.spexliu.top/videos/{video_id}/config'
            api_headers = cls.headers.copy()
            api_headers.update({
                'Origin': 'https://p1.spexliu.top',
                'Referer': f'https://p1.spexliu.top/videos/{video_id}/play',
                'Content-Type': 'application/json',
            })
            api_res = requests.post(config_url, headers=api_headers, timeout=15)
            if api_res.status_code == 200:
                data = api_res.json()
                assert_not_empty(data.get('sources'), "HentaiVietsub Stream Sources")
                logger.info(f"Stream URL: {data['sources'][0]['file']}")

class AniCoreTest:
    base_url = 'https://api.allanime.day/api'
    agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    
    @classmethod
    def _post(cls, query, variables):
        res = requests.post(cls.base_url, headers={
            'User-Agent': cls.agent,
            'Referer': 'https://allmanga.to',
            'Content-Type': 'application/json',
        }, json={'query': query, 'variables': variables}, timeout=15)
        return res.json()

    @classmethod
    def run(cls):
        logger.info("--- Testing AniCore (AllAnime) ---")
        show_query = """
        query($search: SearchInput, $limit: Int, $page: Int, $translationType: VaildTranslationTypeEnumType, $countryOrigin: VaildCountryOriginEnumType) {
          shows(search: $search, limit: $limit, page: $page, translationType: $translationType, countryOrigin: $countryOrigin) {
            edges { _id name thumbnail }
          }
        }
        """
        # Trending
        variables = {
            'search': {'allowAdult': False, 'allowUnknown': False, 'sortBy': 'Top'},
            'limit': 10, 'page': 1, 'translationType': 'sub', 'countryOrigin': 'ALL'
        }
        data = cls._post(show_query, variables)
        edges = data['data']['shows']['edges']
        assert_not_empty(edges, "AniCore Trending edges")
        
        anime_id = edges[0]['_id']
        logger.info(f"Testing episodes for ID: {anime_id}")
        
        # Episodes
        ep_query = """
        query ($showId: String!) {
          show(_id: $showId) { _id availableEpisodesDetail }
        }
        """
        data = cls._post(ep_query, {'showId': anime_id})
        details = data['data']['show']['availableEpisodesDetail']
        eps = details.get('sub') or details.get('dub') or []
        assert_not_empty(eps, "AniCore Episodes list")

class ViAnimeCoreTest:
    base_url = 'https://phimapi.com'
    headers = {'User-Agent': 'AniCli-Flutter/2.0'}

    @classmethod
    def run(cls):
        logger.info("--- Testing ViAnimeCore (PhimAPI) ---")
        # Trending
        url = f'{cls.base_url}/v1/api/danh-sach/phim-le?page=1&country=nhat-ban&limit=10'
        res = requests.get(url, headers=cls.headers, timeout=15)
        data = res.json()
        items = data.get('data', {}).get('items', [])
        assert_not_empty(items, "ViAnimeCore Trending items")
        
        slug = items[0]['slug']
        logger.info(f"Testing Detail/Stream for slug: {slug}")
        
        # Detail & Stream
        res = requests.get(f'{cls.base_url}/phim/{slug}', headers=cls.headers, timeout=15)
        data = res.json()
        episodes = data.get('episodes', [])
        assert_not_empty(episodes, "ViAnimeCore Episodes")
        server_data = episodes[0].get('server_data', [])
        assert_not_empty(server_data, "ViAnimeCore Server Data")
        logger.info(f"Stream URL: {server_data[0]['link_m3u8']}")

# ════════════════════════════════════════════════════════════════════════════
# MANGA CORES
# ════════════════════════════════════════════════════════════════════════════

class ZetTruyenTest:
    base_url = 'https://www.zettruyen.africa'
    api_headers = {
        'accept': 'application/json, text/javascript, */*; q=0.01',
        'user-agent': 'Mozilla/5.0 (Linux; Android 6.0) AppleWebKit/537.36',
        'x-requested-with': 'XMLHttpRequest',
    }

    @classmethod
    def run(cls):
        logger.info("--- Testing ZetTruyen ---")
        # Trending
        res = requests.get(f'{cls.base_url}/api/comics/top', headers=cls.api_headers, timeout=15)
        data = res.json().get('data', {})
        assert_not_empty(data.get('top_day'), "ZetTruyen Top Day")
        
        slug = data['top_day'][0]['slug']
        logger.info(f"Testing Chapters for slug: {slug}")
        
        # Chapters
        res = requests.get(f'{cls.base_url}/api/comics/{slug}/chapters?per_page=10&order=desc', headers=cls.api_headers, timeout=15)
        chapters = res.json().get('data', {}).get('chapters', [])
        assert_not_empty(chapters, "ZetTruyen Chapters list")

class MangaDexTest:
    base_url = 'https://api.mangadex.org'
    
    @classmethod
    def run(cls):
        logger.info("--- Testing MangaDex ---")
        # Search/Trending
        res = requests.get(f'{cls.base_url}/manga?limit=10&includes[]=cover_art', timeout=15)
        data = res.json().get('data', [])
        assert_not_empty(data, "MangaDex Search results")
        
        manga_id = data[0]['id']
        logger.info(f"Testing Feed for ID: {manga_id}")
        
        # Feed
        res = requests.get(f'{cls.base_url}/manga/{manga_id}/feed?limit=10&translatedLanguage[]=en', timeout=15)
        chapters = res.json().get('data', [])
        assert_not_empty(chapters, "MangaDex Chapters")
        
        chapter_id = chapters[0]['id']
        # Pages
        res = requests.get(f'{cls.base_url}/at-home/server/{chapter_id}', timeout=15)
        data = res.json()
        assert_not_empty(data.get('chapter', {}).get('data'), "MangaDex Pages")

class AllMangaTest:
    base_url = 'https://api.allanime.day/api'
    search_hash = '2d48e19fb67ddcac42fbb885204b6abb0a84f406f15ef83f36de4a66f49f651a'
    
    @classmethod
    def run(cls):
        logger.info("--- Testing AllManga ---")
        variables = {
            'search': {'query': 'One Piece', 'isManga': True},
            'limit': 10, 'page': 1, 'translationType': 'sub', 'countryOrigin': 'ALL'
        }
        extensions = {'persistedQuery': {'version': 1, 'sha256Hash': cls.search_hash}}
        params = {
            'variables': json.dumps(variables),
            'extensions': json.dumps(extensions)
        }
        res = requests.get(cls.base_url, params=params, headers={'Referer': 'https://allmanga.to'}, timeout=15)
        data = res.json()
        edges = data.get('data', {}).get('mangas', {}).get('edges', [])
        assert_not_empty(edges, "AllManga Search edges")

# ════════════════════════════════════════════════════════════════════════════
# MAIN RUNNER
# ════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    success = True
    tests = [
        HentaiVietsubTest,
        AniCoreTest,
        ViAnimeCoreTest,
        ZetTruyenTest,
        MangaDexTest,
        AllMangaTest
    ]
    
    for test in tests:
        try:
            test.run()
            logger.info(f"✅ {test.__name__} passed.")
        except Exception as e:
            logger.error(f"❌ {test.__name__} failed: {e}", exc_info=True)
            success = False
            # As requested: stop if one fails
            break
            
    if not success:
        logger.critical("Final Result: FAIL")
        sys.exit(1)
    
    logger.info("Final Result: ALL PASSED")
    sys.exit(0)
