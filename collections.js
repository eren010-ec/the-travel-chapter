// Trip collections — named groups of trips (by the trips.category column, or a title
// keyword) shared by the home page's category circles / destination tiles and the
// trips.html ?c=<key> filter. Labels are per language; TC_I18N picks the current one.
(function (global) {
  'use strict';

  function cats(list) { return function (t) { return list.indexOf(String(t.category || '').toUpperCase()) !== -1; }; }
  function titleHas(word) { return function (t) { return String(t.title || '').toUpperCase().indexOf(word) !== -1; }; }

  var ASIA = ['CHINA', 'JAPAN', 'KOREA', 'VIETNAM', 'THAILAND', 'BANGKOK', 'TAIWAN', 'INDONESIA', 'BALI', 'BATAM',
              'KRABI', 'MALDIVES', 'SRI LANKA', 'UZBEKISTAN'];

  // image: a fixed local picture; otherwise the cover of the `prefer` trip (title match)
  // or of the first trip in the collection.
  var C = {
    sarawak:  { label: { en: 'Sarawak', zh: '砂拉越', ms: 'Sarawak' }, match: cats(['KUCHING']), image: 'img/cat-sarawak.webp' },
    malaysia: { label: { en: 'Malaysia', zh: '马来西亚', ms: 'Malaysia' }, match: cats(['KUCHING', 'SEMPORNA', 'TIOMAN']), prefer: 'SEMPORNA' },
    asia:     { label: { en: 'Asia', zh: '亚洲', ms: 'Asia' }, match: cats(ASIA), prefer: 'TOKYO' },
    europe:   { label: { en: 'Europe', zh: '欧洲', ms: 'Eropah' }, match: cats(['EUROPE']), prefer: 'EUROPE' },
    oceania:  { label: { en: 'Oceania', zh: '大洋洲', ms: 'Oceania' }, match: cats(['NZ']) },
    cruise:   { label: { en: 'Cruise', zh: '邮轮', ms: 'Pelayaran' }, match: cats(['CRUISE']), prefer: 'ROYAL' },
    island:   { label: { en: 'Island & Beach', zh: '海岛度假', ms: 'Pulau & Pantai' },
                match: cats(['BALI', 'MALDIVES', 'KRABI', 'SEMPORNA', 'TIOMAN', 'BATAM']), image: 'img/cat-island.webp' },
    private:  { label: { en: 'Private Tour', zh: '私人团', ms: 'Lawatan Peribadi' }, match: titleHas('PRIVATE') },
    group:    { label: { en: 'Group Tour', zh: '跟团游', ms: 'Lawatan Berkumpulan' },
                match: function (t) { return !titleHas('PRIVATE')(t); }, prefer: 'HOKKAIDO' },
    china:    { label: { en: 'China', zh: '中国', ms: 'China' }, match: cats(['CHINA']), prefer: 'ZHANGJIAJIE' },
    japan:    { label: { en: 'Japan', zh: '日本', ms: 'Jepun' }, match: cats(['JAPAN']), prefer: 'TOKYO' },
    korea:    { label: { en: 'Korea', zh: '韩国', ms: 'Korea' }, match: cats(['KOREA']) },
    thailand: { label: { en: 'Thailand', zh: '泰国', ms: 'Thailand' }, match: cats(['THAILAND', 'BANGKOK', 'KRABI']), prefer: 'BANGKOK' },
    vietnam:  { label: { en: 'Vietnam', zh: '越南', ms: 'Vietnam' }, match: cats(['VIETNAM']) },
    taiwan:   { label: { en: 'Taiwan', zh: '台湾', ms: 'Taiwan' }, match: cats(['TAIWAN']) },
    bali:     { label: { en: 'Bali', zh: '巴厘岛', ms: 'Bali' }, match: cats(['BALI', 'INDONESIA']), prefer: 'BALI' },
    maldives: { label: { en: 'Maldives', zh: '马尔代夫', ms: 'Maldives' }, match: cats(['MALDIVES']) },
    world:    { label: { en: 'Middle East & Africa', zh: '中东与非洲', ms: 'Timur Tengah & Afrika' },
                match: function (t) { return /EGYPT|MOROCCO|TUNISIA|TURKEY|DUBAI/.test(String(t.title || '').toUpperCase()); }, prefer: 'EGYPT' }
  };

  function label(key) {
    var c = C[key]; if (!c) return key;
    var lang = (global.TC_I18N && TC_I18N.lang) || 'en';
    return c.label[lang] || c.label.en;
  }
  function trips(key, all) { var c = C[key]; return c ? (all || []).filter(c.match) : []; }
  function image(key, all) {
    var c = C[key]; if (!c) return '';
    if (c.image) return c.image;
    var list = trips(key, all).filter(function (t) { return t.cover_image; });
    var pick = c.prefer && list.filter(titleHas(c.prefer))[0];
    return (pick || list[0] || {}).cover_image || '';
  }

  global.TC_COLLECTIONS = { all: C, label: label, trips: trips, image: image };
})(window);
