// Shared i18n engine for the member-facing site (index.html, login.html, dashboard.html).
// Usage: include this script, then call TC_I18N.applyStatic() as the FIRST line of the
// page's own inline script (don't rely solely on the DOMContentLoaded auto-apply below —
// some pages read translated text synchronously during parsing, e.g. index.html's
// manifesto word-split, so translations must already be in the DOM before that runs).
(function (global) {
  'use strict';
  const STORAGE_KEY = 'tc_lang';
  const SUPPORTED = ['en', 'zh', 'ms'];

  const DICT = {
    en: {
      // ── shared ──
      'tier.explorer': 'Explorer', 'tier.premier': 'Premier', 'tier.elite': 'Elite',
      'status.pending': 'pending', 'status.confirmed': 'confirmed', 'status.cancelled': 'cancelled', 'status.completed': 'completed',
      'status.redeemed': 'redeemed', 'status.rewarded': 'rewarded',
      // Generic "Chapter {word}" builder used when destination chapters come from the CMS
      // (which may have more/fewer than the 5 hardcoded fallback chapters).
      'journal.chapter_label': 'Chapter {word}',
      'journal.chapter_word1': 'One', 'journal.chapter_word2': 'Two', 'journal.chapter_word3': 'Three', 'journal.chapter_word4': 'Four', 'journal.chapter_word5': 'Five',
      'journal.chapter_word6': 'Six', 'journal.chapter_word7': 'Seven', 'journal.chapter_word8': 'Eight', 'journal.chapter_word9': 'Nine', 'journal.chapter_word10': 'Ten',

      // ── index.html: nav ──
      'nav.destinations': 'Destinations', 'nav.trips': 'Trips', 'nav.membership': 'Membership',
      'nav.about': 'About', 'nav.contact': 'Contact', 'nav.signin': 'Sign In',

      // ── index.html: hero / journal intro ──
      'hero.eyebrow': 'Curated Journeys',
      'hero.heading': 'Travel Beyond<br>the <em>Ordinary</em>',
      'hero.subtext': 'The Travel Chapter curates extraordinary journeys for discerning travellers — from intimate ryokans in Kyoto to private yacht charters along the Amalfi Coast.',
      'hero.cta_primary': 'Explore Trips',

      // ── index.html: destinations ──
      'destinations.eyebrow': 'Where We Go',
      'destinations.heading': 'Handpicked<br><em>Destinations</em>',
      'destinations.subtext': 'Every destination is personally vetted by our travel curators — chosen for their cultural depth, natural beauty and rare experiences.',

      'journal.toc1': 'The Beginning — Kyoto',
      'journal.toc2': 'Word Traveled Fast — Amalfi',
      'journal.toc3': 'Learning to Listen — Marrakech',
      'journal.toc4': 'Slowing Down — Luang Prabang',
      'journal.toc5': 'To the Edge of the World — Patagonia',

      // ── index.html: journal chapters ──
      'journal.ch1.badge': 'Chapter One', 'journal.ch1.name': 'The Beginning', 'journal.ch1.region': 'Kyoto, Japan · 2012',
      'journal.ch1.caption': 'It started with one traveller, a single notebook, and a solo trip to Kyoto that changed everything — and a promise to never plan an ordinary itinerary again.',
      'journal.ch2.badge': 'Chapter Two', 'journal.ch2.name': 'Word Traveled Fast', 'journal.ch2.region': 'Amalfi Coast · 2015',
      'journal.ch2.caption': "Friends who'd heard about that first trip began asking for help planning their own. By the time we were chartering yachts along Italy's coast, trust had quietly become our business.",
      'journal.ch3.badge': 'Chapter Three', 'journal.ch3.name': 'Learning to Listen', 'journal.ch3.region': 'Marrakech, Morocco · 2018',
      'journal.ch3.caption': 'We learned our best itineraries were never written from a desk — they came from local guides who knew which alley led to the Marrakech no guidebook could show us.',
      'journal.ch4.badge': 'Chapter Four', 'journal.ch4.name': 'Slowing Down', 'journal.ch4.region': 'Luang Prabang, Laos · 2021',
      'journal.ch4.caption': 'Somewhere along the Mekong at dawn, we understood what travel was really for — not ticking boxes, but standing still long enough to feel something.',
      'journal.ch5.badge': 'Chapter Five', 'journal.ch5.name': 'To the Edge of the World', 'journal.ch5.region': 'Patagonia · 2024',
      'journal.ch5.caption': "That same restless curiosity has since carried our travellers to Patagonia's glaciers and beyond — proof that a decade on, we're still chasing that first Kyoto feeling.",

      // ── index.html: epilogue ──
      'journal.epilogue_eyebrow': 'Epilogue',
      'journal.epilogue_heading': 'Your chapter starts here',
      'journal.stat1_lbl': 'Destinations', 'journal.stat2_lbl': 'Happy Travellers', 'journal.stat3_lbl': 'Experience',

      // ── index.html: manifesto ──
      'manifesto.text': 'We believe travel should move you, not just take you somewhere. Every chapter we craft turns distance into memory — and memory into the story you carry home.',

      // ── index.html: featured trips ──
      'trips.eyebrow': 'Our Journeys',
      'trips.heading': 'Featured <em>Trips</em>',
      'trips.subtext': 'Each journey is crafted with intention — expert guides, intimate group sizes and access to experiences no ordinary tourist agency can offer.',
      'trips.book_now': 'Book Now', 'trips.per_person': '/ person', 'trips.max': 'Max', 'trips.days': 'days', 'trips.from': 'From',
      'trips.card1.name': 'Kyoto in Autumn', 'trips.card1.desc': "Chase the crimson maple leaves through Kyoto's finest temples and hidden gardens.", 'trips.card1.duration': '8 days', 'trips.card1.pax': 'Max 10', 'trips.card1.window': 'Oct – Nov',
      'trips.card2.name': 'Amalfi by Yacht', 'trips.card2.desc': 'A private yacht journey along the Amalfi Coast — secluded coves, fresh seafood and golden sunsets.', 'trips.card2.duration': '6 days', 'trips.card2.pax': 'Max 8', 'trips.card2.window': 'Jun – Jul',
      'trips.card3.name': 'Marrakech & Beyond', 'trips.card3.desc': 'Imperial cities, Sahara desert camps and Atlas mountain villages — Morocco in full depth.', 'trips.card3.duration': '9 days', 'trips.card3.pax': 'Max 14', 'trips.card3.window': 'Sep – Oct',
      'trips.card4.name': 'Mekong River Journey', 'trips.card4.desc': 'Slow travel through Laos on a restored river cruiser — monasteries, markets and misty mornings.', 'trips.card4.duration': '10 days', 'trips.card4.pax': 'Max 12', 'trips.card4.window': 'Nov – Jan',
      'trips.card5.name': 'Patagonia Wilderness', 'trips.card5.desc': 'Trek the W Circuit with expert mountain guides — glaciers, granite towers and the end of the world.', 'trips.card5.duration': '12 days', 'trips.card5.pax': 'Max 8', 'trips.card5.window': 'Dec – Feb',
      'trips.card6.name': 'Elite Japan Immersion', 'trips.card6.desc': 'Private geisha dinners, bullet-train journeys and exclusive onsen retreats — Japan at its most intimate.', 'trips.card6.duration': '14 days', 'trips.card6.pax': 'Max 6', 'trips.card6.window': 'Oct · Mar',

      // ── index.html: membership ──
      'membership.eyebrow': 'Membership',
      'membership.heading': 'Choose Your <em>Chapter</em>',
      'membership.subtext': 'Every member starts as an Explorer and earns points with every journey — unlocking richer experiences as you travel more.',
      'membership.most_popular': 'Most Popular',
      'membership.explorer.pts': '0 – 999 Points', 'membership.premier.pts': '1,000 – 4,999 Points', 'membership.elite.pts': '5,000+ Points',
      'membership.explorer.perk1': 'Access to all Explorer trips', 'membership.explorer.perk2': '1 point per RM spent', 'membership.explorer.perk3': 'Email travel updates', 'membership.explorer.perk4': '24/7 member support',
      'membership.premier.perk1': 'All Explorer benefits', 'membership.premier.perk2': 'Access to Premier trips', 'membership.premier.perk3': 'Priority booking windows', 'membership.premier.perk4': 'Complimentary travel insurance', 'membership.premier.perk5': 'Exclusive member events',
      'membership.elite.perk1': 'All Premier benefits', 'membership.elite.perk2': 'Access to Elite-only trips', 'membership.elite.perk3': 'Dedicated travel concierge', 'membership.elite.perk4': 'Airport lounge access', 'membership.elite.perk5': 'Annual gift & surprises',

      // ── index.html: about ──
      'about.eyebrow': 'Our Story',
      'about.heading': 'Travel with<br><em>Purpose</em>',
      'about.badge_val': '12+', 'about.badge_lbl': 'Years curating<br>journeys',
      'about.p1': 'The Travel Chapter was born from a simple belief — that travel should be more than a checklist. It should leave you changed, connected and hungry for more.',
      'about.p2': 'We are a team of passionate travellers who have spent over a decade building relationships with local guides, boutique properties and cultural experts across the world.',
      'about.p3': 'Every itinerary we craft is a chapter in your story — carefully written, beautifully paced and impossible to forget.',
      'about.value1.title': 'Local First', 'about.value1.desc': 'We work with local guides and communities at every destination.',
      'about.value2.title': 'Curated Quality', 'about.value2.desc': 'Every hotel, guide and experience is personally vetted by our team.',
      'about.value3.title': 'Responsible', 'about.value3.desc': 'We travel with care — for people, culture and the environment.',
      'about.value4.title': 'Always There', 'about.value4.desc': 'From booking to return, our team is with you every step of the way.',

      // ── index.html: testimonials ──
      'testimonials.eyebrow': 'Traveller Stories',
      'testimonials.heading': 'What Our Members <em>Say</em>',
      'testimonials.card1.text': '"Kyoto in autumn was everything I imagined and more. The access to private temples at dawn was something I could never have arranged on my own."',
      'testimonials.card1.trip': 'Kyoto in Autumn · Premier Member',
      'testimonials.card2.text': '"The Amalfi yacht trip was beyond anything I expected. Waking up in a secluded cove every morning — absolute perfection. Already booked my next trip."',
      'testimonials.card2.trip': 'Amalfi by Yacht · Elite Member',
      'testimonials.card3.text': '"The Travel Chapter doesn\'t just plan trips — they craft experiences. My Mekong River journey felt like a dream I didn\'t want to wake up from."',
      'testimonials.card3.trip': 'Mekong River Journey · Explorer Member',

      // ── index.html: cta banner ──
      'cta.heading': 'Ready to Begin Your <em>Chapter</em>?',
      'cta.subtext': 'Join thousands of discerning travellers who have trusted us with their most precious journeys.',
      'cta.primary': 'Talk to Us',

      // ── index.html: contact ──
      'contact.eyebrow': 'Get in Touch',
      'contact.heading': "Let's Plan Your<br><em>Journey</em>",
      'contact.subtext': 'Have a destination in mind? Want to know more about our membership? Our team is happy to help you find the perfect trip.',
      'contact.email_label': 'Email Us', 'contact.phone_label': 'Call Us', 'contact.address_label': 'Visit Us',
      'contact.address_value': 'Kuala Lumpur, Malaysia',
      'contact.form.first_name': 'First Name', 'contact.form.last_name': 'Last Name', 'contact.form.email': 'Email Address',
      'contact.form.interested': 'Interested In', 'contact.form.select_placeholder': 'Select a destination or trip…',
      'contact.form.message': 'Your Message', 'contact.form.message_placeholder': 'Tell us about your dream trip…',
      'contact.form.submit': 'Send Message', 'contact.form.custom_option': 'Custom / Other',
      'contact.form.first_name_ph': 'Jane', 'contact.form.last_name_ph': 'Smith', 'contact.form.email_ph': 'jane@example.com',

      // ── index.html: footer ──
      'footer.tagline': 'Curating extraordinary journeys for discerning travellers since 2012. Based in Kuala Lumpur, travelling the world.',
      'footer.explore_title': 'Explore', 'footer.members_title': 'Members', 'footer.contact_title': 'Contact',
      'footer.link_destinations': 'Destinations', 'footer.link_trips': 'Featured Trips', 'footer.link_membership': 'Membership', 'footer.link_about': 'Our Story',
      'footer.link_signin': 'Sign In', 'footer.link_dashboard': 'Dashboard', 'footer.link_message': 'Send a Message',
      'footer.copyright': '© 2026 The Travel Chapter. All rights reserved.',
      'footer.location': 'Crafted with care in Kuala Lumpur 🇲🇾',

      // ── index.html: install banner ──
      'install.title': 'Install The Travel Chapter',
      'install.subtext': 'Add to your home screen for quick, full-screen access.',
      'install.button': 'Install', 'install.dismiss_aria': 'Dismiss',
      'install.ios_subtext': 'Tap Share, then "Add to Home Screen" for quick, full-screen access.',

      // ── index.html: toasts ──
      'toast.contact_sent': "Message sent! We'll be in touch within 24 hours ✓",

      // ── login.html ──
      'login.back_to_website': 'Back to Website',
      'login.hero_eyebrow': 'Member Portal',
      'login.hero_heading': 'Your Journey<br>Starts <em>Here</em>',
      'login.hero_subtext': 'Sign in to access your bookings, explore curated trips, and manage your membership — all in one place.',
      'login.explore_destinations': 'Explore Destinations', 'login.our_story': 'Our Story',
      'login.brand_sub': 'Member Portal',
      'login.tab_signin': 'Sign In', 'login.tab_register': 'Join Us',
      'login.phone_label': 'Phone Number', 'login.password_label': 'Password',
      'login.phone_placeholder': '12 345 6789', 'login.password_placeholder': '••••••••',
      'login.forgot_link': 'Forgot password?',
      'login.signin_button': 'Sign In', 'login.signin_loading': 'Signing in…',
      'login.new_here': 'New here?', 'login.create_account_link': 'Create an account',
      'login.send_code_button': 'Send Verification Code',
      'login.finish_profile_label': 'Phone verified. Just a few more details to finish setting up your account.',
      'login.first_name_label': 'First Name', 'login.last_name_label': 'Last Name',
      'login.first_name_placeholder': 'Jane', 'login.last_name_placeholder': 'Smith',
      'login.email_label': 'Email', 'login.email_placeholder': 'jane@example.com',
      'login.reg_password_placeholder': 'Min. 8 characters',
      'login.create_account_button': 'Create Account', 'login.creating_loading': 'Creating account…',
      'login.already_member': 'Already a member?', 'login.signin_link': 'Sign in',
      'login.verify_default_label': 'We sent an SMS code to your phone.',
      'login.verify_sent': 'We sent an SMS code to {phone}.',
      'login.verify_code_label': 'Verification Code', 'login.code_placeholder': '6-digit code',
      'login.verify_button': 'Verify & Continue', 'login.verifying_loading': 'Verifying…',
      'login.resend_code': 'Resend code', 'login.resend_code_cooldown': 'Resend code ({secs}s)',
      'login.wrong_number': 'Wrong number?',
      'login.forgot_send_button': 'Send SMS Code', 'login.sending_loading': 'Sending…',
      'login.back_to_signin': 'Back to sign in',
      'login.forgot_verify_default_label': 'Enter the code we sent by SMS.',
      'login.forgot_verify_sent': 'Enter the code we sent to {phone} by SMS.',
      'login.new_password_label': 'New Password',
      'login.reset_button': 'Reset Password', 'login.resetting_loading': 'Resetting…',
      'login.err_fill_fields': 'Please fill in all fields.',
      'login.err_invalid_phone': 'Enter your phone number with country code, e.g. +6591234567.',
      'login.err_fill_required': 'Please fill in all required fields.',
      'login.err_invalid_email': 'Enter a valid email address.',
      'login.err_password_length': 'Password must be at least 8 characters.',
      'login.err_enter_code': 'Enter the code sent by SMS.',
      'login.err_fill_code_password': 'Enter the code and your new password.',
      'login.err_admin_account': 'This is an admin/staff account — please sign in at the admin portal instead.',
      'login.toast_welcome': 'Welcome to The Travel Chapter!',
      'login.toast_code_resent': 'Code resent via SMS.',
      'login.toast_password_updated': 'Password updated — signing you in…',

      // ── dashboard.html ──
      'dash.tagline': 'Member Portal', 'dash.loading': 'Loading…', 'dash.signout': 'Sign Out',
      'dash.nav_overview': 'Overview', 'dash.nav_trips': 'Browse Trips', 'dash.nav_bookings': 'My Bookings',
      'dash.nav_referrals': 'Referrals', 'dash.nav_luckydraw': 'Lucky Draw', 'dash.nav_membership': 'Membership', 'dash.nav_profile': 'My Profile',
      'dash.overview_welcome': 'Welcome back,', 'dash.overview_subtitle': "Here's a snapshot of your journey with us.",
      'dash.stat_bookings': 'Total Bookings', 'dash.stat_points': 'Tier Points', 'dash.stat_tier': 'Membership Tier',
      'dash.recent_bookings': 'Recent Bookings', 'dash.tier_progress': 'Tier Progress',
      'dash.no_bookings_overview': 'No bookings yet.<br>Browse trips to get started!',
      'dash.pts_to_premier': '{n} pts to Premier', 'dash.pts_to_elite': '{n} pts to Elite',
      'dash.max_tier': 'Maximum tier reached 👑', 'dash.pts_suffix': 'pts',
      'dash.browse_heading': 'Browse <em>Trips</em>', 'dash.browse_subtitle': 'Discover curated journeys matched to your membership tier.',
      'dash.loading_trips': 'Loading trips…', 'dash.no_trips': 'No trips available right now.',
      'dash.book_now': 'Book Now', 'dash.locked_suffix': 'only', 'dash.max_label': 'Max', 'dash.days_label': 'days', 'dash.per_person': '/ person',
      'dash.bookings_heading': 'My <em>Bookings</em>', 'dash.bookings_subtitle': 'Track all your past and upcoming journeys.',
      'dash.no_bookings': 'No bookings yet.<br>Head to Browse Trips to plan your first journey!',
      'dash.traveller_singular': 'traveller', 'dash.traveller_plural': 'travellers',
      'dash.referrals_heading': 'My <em>Referrals</em>', 'dash.referrals_subtitle': 'Share your code with friends — you both get rewarded when they book.',
      'dash.your_code': 'Your Referral Code', 'dash.copy_code': '📋 Copy Code',
      'dash.code_copied': 'Code {code} copied ✓', 'dash.copy_failed': 'Could not copy — copy it manually.',
      'dash.my_referrals': 'My Referrals', 'dash.current_promotion': 'Current Promotion',
      'dash.promo_text': 'Share your code — you earn <strong style="color:var(--gold);">{referrer}</strong>, your friend gets <strong style="color:var(--gold);">{referee}</strong> off their first trip.',
      'dash.pending_friend': 'Pending friend', 'dash.no_referrals': 'No referrals yet.<br>Share your code to get started!',
      'dash.luckydraw_heading': 'Lucky <em>Draw</em>', 'dash.luckydraw_subtitle': 'Every eligible booking or referral is an entry — check back here for results.',
      'dash.my_wins': 'My Wins', 'dash.no_wins': 'No wins yet — stay tuned!', 'dash.lucky_draw_fallback_name': 'Lucky Draw',
      'dash.membership_heading': 'My <em>Membership</em>', 'dash.membership_subtitle': 'Your tier unlocks exclusive trips and privileges.',
      'dash.current_status': 'Current Status', 'dash.tier_comparison': 'Tier Comparison', 'dash.your_tier': 'Your Tier',
      'dash.earn_more_premier': 'Earn {n} more points to reach Premier', 'dash.earn_more_elite': 'Earn {n} more points to reach Elite',
      'dash.highest_tier': "You've reached our highest tier 👑", 'dash.member_suffix': 'Member',
      'dash.tier_explorer_pts': '0 – 999 pts', 'dash.tier_premier_pts': '1,000 – 4,999 pts', 'dash.tier_elite_pts': '5,000+ pts',
      'dash.tier_explorer_perk1': 'Access to all Explorer trips', 'dash.tier_explorer_perk2': '1 point per RM spent', 'dash.tier_explorer_perk3': 'Email travel updates', 'dash.tier_explorer_perk4': '24/7 support chat',
      'dash.tier_premier_perk1': 'All Explorer benefits', 'dash.tier_premier_perk2': 'Access to Premier trips', 'dash.tier_premier_perk3': 'Priority booking windows', 'dash.tier_premier_perk4': 'Complimentary travel insurance', 'dash.tier_premier_perk5': 'Exclusive member events',
      'dash.tier_elite_perk1': 'All Premier benefits', 'dash.tier_elite_perk2': 'Access to Elite-only trips', 'dash.tier_elite_perk3': 'Dedicated travel concierge', 'dash.tier_elite_perk4': 'Airport lounge access', 'dash.tier_elite_perk5': 'Annual gift & surprises',
      'dash.profile_heading': 'My <em>Profile</em>', 'dash.profile_subtitle': 'Keep your details up to date for a seamless booking experience.',
      'dash.personal_info': 'Personal Information',
      'dash.first_name': 'First Name', 'dash.last_name': 'Last Name', 'dash.phone_number': 'Phone Number',
      'dash.dob': 'Date of Birth', 'dash.nationality': 'Nationality', 'dash.passport': 'Passport Number',
      'dash.first_name_ph': 'Jane', 'dash.last_name_ph': 'Smith', 'dash.phone_ph': '+60 12 345 6789', 'dash.nationality_ph': 'Malaysian', 'dash.passport_ph': 'A12345678',
      'dash.save_changes': 'Save Changes', 'dash.saving': 'Saving…', 'dash.profile_saved': 'Profile saved ✓', 'dash.error_prefix': 'Error: ',
      'dash.modal_book_trip': 'Book Trip', 'dash.departure_date': 'Departure Date', 'dash.num_travellers': 'Number of Travellers',
      'dash.special_requests': 'Special Requests (optional)', 'dash.special_requests_ph': 'Dietary requirements, accessibility needs…',
      'dash.estimated_total': 'Estimated Total', 'dash.cancel': 'Cancel',
      'dash.confirm_booking': 'Confirm Booking', 'dash.confirming': 'Confirming…', 'dash.no_dates': 'No dates available',
      'dash.select_departure_err': 'Please select a departure date.', 'dash.booking_failed': 'Booking failed: ',
      'dash.booking_sent': "Booking request sent! We'll confirm shortly ✈️",
    },

    zh: {
      'tier.explorer': '探索者', 'tier.premier': '尊享', 'tier.elite': '至尊',
      'status.pending': '待处理', 'status.confirmed': '已确认', 'status.cancelled': '已取消', 'status.completed': '已完成',
      'status.redeemed': '已兑换', 'status.rewarded': '已奖励',
      'journal.chapter_label': '第{word}章',
      'journal.chapter_word1': '一', 'journal.chapter_word2': '二', 'journal.chapter_word3': '三', 'journal.chapter_word4': '四', 'journal.chapter_word5': '五',
      'journal.chapter_word6': '六', 'journal.chapter_word7': '七', 'journal.chapter_word8': '八', 'journal.chapter_word9': '九', 'journal.chapter_word10': '十',

      'nav.destinations': '目的地', 'nav.trips': '行程', 'nav.membership': '会员', 'nav.about': '关于我们', 'nav.contact': '联系我们', 'nav.signin': '登录',

      'hero.eyebrow': '精心策划的旅程',
      'hero.heading': '超越平凡<br>探索<em>非凡</em>',
      'hero.subtext': 'The Travel Chapter 为品味独到的旅行者精心策划非凡旅程——从京都的静谧旅馆到阿马尔菲海岸的私人游艇之旅。',
      'hero.cta_primary': '探索行程',

      'destinations.eyebrow': '我们的足迹',
      'destinations.heading': '精心甄选<br><em>目的地</em>',
      'destinations.subtext': '每一个目的地都经过我们旅行策划师的亲自实地考察——因其深厚的文化底蕴、自然美景与独特体验而入选。',

      'journal.toc1': '起点 — 京都',
      'journal.toc2': '口碑相传 — 阿马尔菲',
      'journal.toc3': '学会倾听 — 马拉喀什',
      'journal.toc4': '慢下脚步 — 琅勃拉邦',
      'journal.toc5': '世界的尽头 — 巴塔哥尼亚',

      'journal.ch1.badge': '第一章', 'journal.ch1.name': '起点', 'journal.ch1.region': '日本京都 · 2012年',
      'journal.ch1.caption': '一切始于一位旅行者、一本笔记本，和一次改变一切的京都独行——从此立誓，再也不安排平凡的行程。',
      'journal.ch2.badge': '第二章', 'journal.ch2.name': '口碑相传', 'journal.ch2.region': '阿马尔菲海岸 · 2015年',
      'journal.ch2.caption': '听闻第一次旅程的朋友们纷纷前来求助，请我们为他们规划旅行。等到我们开始在意大利海岸包租游艇时，信任已悄然成为我们的事业。',
      'journal.ch3.badge': '第三章', 'journal.ch3.name': '学会倾听', 'journal.ch3.region': '摩洛哥马拉喀什 · 2018年',
      'journal.ch3.caption': '我们明白，最好的行程从不是坐在办公桌前写就的——而是来自当地向导,他们知道哪条小巷能带你走进任何指南都无法呈现的马拉喀什。',
      'journal.ch4.badge': '第四章', 'journal.ch4.name': '慢下脚步', 'journal.ch4.region': '老挝琅勃拉邦 · 2021年',
      'journal.ch4.caption': '在湄公河畔的某个清晨,我们终于懂得旅行真正的意义——不是打卡清单,而是静静伫立,久到能感受些什么。',
      'journal.ch5.badge': '第五章', 'journal.ch5.name': '世界的尽头', 'journal.ch5.region': '巴塔哥尼亚 · 2024年',
      'journal.ch5.caption': '正是那份不曾停歇的好奇心，将我们的旅行者带到了巴塔哥尼亚的冰川及更远之地——十年过去，我们依旧追寻着当初在京都的那份悸动。',

      'journal.epilogue_eyebrow': '尾声',
      'journal.epilogue_heading': '你的篇章，由此开始',
      'journal.stat1_lbl': '目的地', 'journal.stat2_lbl': '满意旅行者', 'journal.stat3_lbl': '年经验',

      'manifesto.text': '我们相信，旅行应该触动你的内心，而不只是带你到达某处。我们打造的每一段旅程，都将距离化为回忆——将回忆化为你带回家的故事。',

      'trips.eyebrow': '我们的旅程',
      'trips.heading': '精选<em>行程</em>',
      'trips.subtext': '每一段旅程都用心打造——专业向导、小巧团体规模，以及一般旅行社无法提供的独特体验。',
      'trips.book_now': '立即预订', 'trips.per_person': '/ 每人', 'trips.max': '最多', 'trips.days': '天', 'trips.from': '起价',
      'trips.card1.name': '京都赏秋', 'trips.card1.desc': '穿梭京都最美的寺庙与隐秘花园，追逐火红的枫叶。', 'trips.card1.duration': '8天', 'trips.card1.pax': '最多10人', 'trips.card1.window': '10月 – 11月',
      'trips.card2.name': '阿马尔菲游艇之旅', 'trips.card2.desc': '沿阿马尔菲海岸的私人游艇之旅——静谧海湾、新鲜海鲜与金色日落。', 'trips.card2.duration': '6天', 'trips.card2.pax': '最多8人', 'trips.card2.window': '6月 – 7月',
      'trips.card3.name': '马拉喀什深度之旅', 'trips.card3.desc': '帝王之城、撒哈拉沙漠营地与阿特拉斯山村——深度探索摩洛哥。', 'trips.card3.duration': '9天', 'trips.card3.pax': '最多14人', 'trips.card3.window': '9月 – 10月',
      'trips.card4.name': '湄公河之旅', 'trips.card4.desc': '乘坐修复的河船慢游老挝——寺庙、市集与薄雾清晨。', 'trips.card4.duration': '10天', 'trips.card4.pax': '最多12人', 'trips.card4.window': '11月 – 1月',
      'trips.card5.name': '巴塔哥尼亚荒野探险', 'trips.card5.desc': '在专业向导带领下徒步W线路——冰川、花岗岩塔与世界尽头。', 'trips.card5.duration': '12天', 'trips.card5.pax': '最多8人', 'trips.card5.window': '12月 – 2月',
      'trips.card6.name': '至尊日本深度体验', 'trips.card6.desc': '私人艺伎晚宴、新干线旅程与专属温泉——最私密的日本体验。', 'trips.card6.duration': '14天', 'trips.card6.pax': '最多6人', 'trips.card6.window': '10月 · 3月',

      'membership.eyebrow': '会员',
      'membership.heading': '选择你的<em>篇章</em>',
      'membership.subtext': '每位会员均从探索者等级开始，每一次旅程都能积累积分——旅行越多，解锁的体验越丰富。',
      'membership.most_popular': '最受欢迎',
      'membership.explorer.pts': '0 – 999 积分', 'membership.premier.pts': '1,000 – 4,999 积分', 'membership.elite.pts': '5,000+ 积分',
      'membership.explorer.perk1': '畅享所有探索者行程', 'membership.explorer.perk2': '每消费1令吉获1积分', 'membership.explorer.perk3': '电邮旅行资讯', 'membership.explorer.perk4': '24小时会员support',
      'membership.premier.perk1': '享有探索者全部权益', 'membership.premier.perk2': '畅享尊享行程', 'membership.premier.perk3': '优先预订通道', 'membership.premier.perk4': '免费旅行保险', 'membership.premier.perk5': '专属会员活动',
      'membership.elite.perk1': '享有尊享全部权益', 'membership.elite.perk2': '畅享至尊专属行程', 'membership.elite.perk3': '专属旅行管家', 'membership.elite.perk4': '机场贵宾室使用权', 'membership.elite.perk5': '年度礼遇与惊喜',

      'about.eyebrow': '我们的故事',
      'about.heading': '带着<em>初心</em><br>去旅行',
      'about.badge_val': '12+', 'about.badge_lbl': '年策划<br>旅程经验',
      'about.p1': 'The Travel Chapter 源于一个简单的信念——旅行不该只是一份清单，而应让你有所改变、有所连结、意犹未尽。',
      'about.p2': '我们是一群充满热忱的旅行者，十多年来在世界各地与当地向导、精品住宿及文化专家建立深厚的合作关系。',
      'about.p3': '我们打造的每一段行程，都是你故事中的一个篇章——精心撰写、节奏优美、令人难忘。',
      'about.value1.title': '本地优先', 'about.value1.desc': '我们与每个目的地的当地向导及社区紧密合作。',
      'about.value2.title': '精挑细选', 'about.value2.desc': '每一间酒店、每一位向导、每一段体验，皆经我们团队亲自把关。',
      'about.value3.title': '负责任旅行', 'about.value3.desc': '我们以关怀之心旅行——关心人、文化与环境。',
      'about.value4.title': '全程陪伴', 'about.value4.desc': '从预订到归程，我们的团队始终与你同在。',

      'testimonials.eyebrow': '旅行者的故事',
      'testimonials.heading': '会员<em>怎么说</em>',
      'testimonials.card1.text': '"京都的秋天完全超出我的想象。清晨独享私人寺庙的体验，是我自己绝对安排不到的。"',
      'testimonials.card1.trip': '京都赏秋 · 尊享会员',
      'testimonials.card2.text': '"阿马尔菲游艇之旅超乎我的预期。每天清晨在静谧海湾醒来——简直完美。已经预订了下一趟旅程。"',
      'testimonials.card2.trip': '阿马尔菲游艇之旅 · 至尊会员',
      'testimonials.card3.text': '"The Travel Chapter 不只是安排行程——他们打造体验。我的湄公河之旅，就像一场舍不得醒来的梦。"',
      'testimonials.card3.trip': '湄公河之旅 · 探索者会员',

      'cta.heading': '准备好开启你的<em>篇章</em>了吗？',
      'cta.subtext': '加入成千上万信赖我们、托付珍贵旅程的品味旅行者。',
      'cta.primary': '联系我们',

      'contact.eyebrow': '联系我们',
      'contact.heading': '为你规划专属<br><em>旅程</em>',
      'contact.subtext': '心中已有目的地？想更了解我们的会员制度？我们的团队乐意协助你找到最合适的旅程。',
      'contact.email_label': '电邮联系', 'contact.phone_label': '致电联系', 'contact.address_label': '拜访我们',
      'contact.address_value': '马来西亚，吉隆坡',
      'contact.form.first_name': '名字', 'contact.form.last_name': '姓氏', 'contact.form.email': '电邮地址',
      'contact.form.interested': '感兴趣的行程', 'contact.form.select_placeholder': '请选择目的地或行程…',
      'contact.form.message': '您的留言', 'contact.form.message_placeholder': '告诉我们您梦想中的旅程…',
      'contact.form.submit': '发送讯息', 'contact.form.custom_option': '自定义 / 其他',
      'contact.form.first_name_ph': 'Jane', 'contact.form.last_name_ph': 'Smith', 'contact.form.email_ph': 'jane@example.com',

      'footer.tagline': '自2012年起，为品味独到的旅行者策划非凡旅程。总部位于吉隆坡，足迹遍及世界。',
      'footer.explore_title': '探索', 'footer.members_title': '会员', 'footer.contact_title': '联系方式',
      'footer.link_destinations': '目的地', 'footer.link_trips': '精选行程', 'footer.link_membership': '会员', 'footer.link_about': '我们的故事',
      'footer.link_signin': '登录', 'footer.link_dashboard': '会员中心', 'footer.link_message': '发送讯息',
      'footer.copyright': '© 2026 The Travel Chapter. 版权所有。',
      'footer.location': '用心打造于马来西亚吉隆坡 🇲🇾',

      'install.title': '安装 The Travel Chapter',
      'install.subtext': '添加至主屏幕，享受快速的全屏体验。',
      'install.button': '安装', 'install.dismiss_aria': '关闭',
      'install.ios_subtext': '点击「分享」，再点选「添加到主屏幕」，即可享受快速的全屏体验。',

      'toast.contact_sent': '讯息已发送！我们将在24小时内与您联系 ✓',

      'login.back_to_website': '返回网站',
      'login.hero_eyebrow': '会员中心',
      'login.hero_heading': '你的旅程<br>从<em>这里</em>开始',
      'login.hero_subtext': '登录以查看您的预订、探索精选行程，并管理您的会员资格——一站式完成。',
      'login.explore_destinations': '探索目的地', 'login.our_story': '我们的故事',
      'login.brand_sub': '会员中心',
      'login.tab_signin': '登录', 'login.tab_register': '立即加入',
      'login.phone_label': '电话号码', 'login.password_label': '密码',
      'login.phone_placeholder': '12 345 6789', 'login.password_placeholder': '••••••••',
      'login.forgot_link': '忘记密码？',
      'login.signin_button': '登录', 'login.signin_loading': '登录中…',
      'login.new_here': '第一次来？', 'login.create_account_link': '创建账户',
      'login.send_code_button': '发送验证码',
      'login.finish_profile_label': '电话已验证。请再填写几项资料以完成账户设置。',
      'login.first_name_label': '名字', 'login.last_name_label': '姓氏',
      'login.first_name_placeholder': 'Jane', 'login.last_name_placeholder': 'Smith',
      'login.email_label': '电子邮件', 'login.email_placeholder': 'jane@example.com',
      'login.reg_password_placeholder': '至少8个字符',
      'login.create_account_button': '创建账户', 'login.creating_loading': '创建账户中…',
      'login.already_member': '已经是会员？', 'login.signin_link': '登录',
      'login.verify_default_label': '我们已通过短信向您的手机发送验证码。',
      'login.verify_sent': '我们已通过短信向 {phone} 发送验证码。',
      'login.verify_code_label': '验证码', 'login.code_placeholder': '6位数验证码',
      'login.verify_button': '验证并继续', 'login.verifying_loading': '验证中…',
      'login.resend_code': '重新发送验证码', 'login.resend_code_cooldown': '重新发送验证码（{secs}秒）',
      'login.wrong_number': '号码错误？',
      'login.forgot_send_button': '通过短信发送验证码', 'login.sending_loading': '发送中…',
      'login.back_to_signin': '返回登录',
      'login.forgot_verify_default_label': '请输入我们通过短信发送的验证码。',
      'login.forgot_verify_sent': '请输入我们通过短信发送至 {phone} 的验证码。',
      'login.new_password_label': '新密码',
      'login.reset_button': '重置密码', 'login.resetting_loading': '重置中…',
      'login.err_fill_fields': '请填写所有栏位。',
      'login.err_invalid_phone': '请输入带国家代码的电话号码，例如 +6591234567。',
      'login.err_fill_required': '请填写所有必填栏位。',
      'login.err_invalid_email': '请输入有效的电子邮件地址。',
      'login.err_password_length': '密码至少需要8个字符。',
      'login.err_enter_code': '请输入我们通过短信发送的验证码。',
      'login.err_fill_code_password': '请输入验证码和新密码。',
      'login.err_admin_account': '这是管理员/员工账户——请前往管理后台登录。',
      'login.toast_welcome': '欢迎加入 The Travel Chapter！',
      'login.toast_code_resent': '验证码已通过短信重新发送。',
      'login.toast_password_updated': '密码已更新——正在为您登录…',

      'dash.tagline': '会员中心', 'dash.loading': '加载中…', 'dash.signout': '退出登录',
      'dash.nav_overview': '概览', 'dash.nav_trips': '浏览行程', 'dash.nav_bookings': '我的预订',
      'dash.nav_referrals': '推荐好友', 'dash.nav_luckydraw': '幸运抽奖', 'dash.nav_membership': '会员等级', 'dash.nav_profile': '个人资料',
      'dash.overview_welcome': '欢迎回来，', 'dash.overview_subtitle': '这是您与我们同行旅程的概览。',
      'dash.stat_bookings': '总预订数', 'dash.stat_points': '等级积分', 'dash.stat_tier': '会员等级',
      'dash.recent_bookings': '近期预订', 'dash.tier_progress': '等级进度',
      'dash.no_bookings_overview': '暂无预订。<br>浏览行程，开启您的旅程！',
      'dash.pts_to_premier': '再获 {n} 积分即可升级至尊享', 'dash.pts_to_elite': '再获 {n} 积分即可升级至至尊',
      'dash.max_tier': '已达最高等级 👑', 'dash.pts_suffix': '积分',
      'dash.browse_heading': '浏览<em>行程</em>', 'dash.browse_subtitle': '发现与您会员等级相匹配的精选旅程。',
      'dash.loading_trips': '加载行程中…', 'dash.no_trips': '目前暂无可用行程。',
      'dash.book_now': '立即预订', 'dash.locked_suffix': '专属', 'dash.max_label': '最多', 'dash.days_label': '天', 'dash.per_person': '/ 每人',
      'dash.bookings_heading': '我的<em>预订</em>', 'dash.bookings_subtitle': '追踪您所有过去与即将到来的旅程。',
      'dash.no_bookings': '暂无预订。<br>前往浏览行程，规划您的第一趟旅程！',
      'dash.traveller_singular': '位旅客', 'dash.traveller_plural': '位旅客',
      'dash.referrals_heading': '我的<em>推荐</em>', 'dash.referrals_subtitle': '与朋友分享您的推荐码——双方预订成功后皆可获得奖励。',
      'dash.your_code': '您的推荐码', 'dash.copy_code': '📋 复制代码',
      'dash.code_copied': '代码 {code} 已复制 ✓', 'dash.copy_failed': '无法复制——请手动复制。',
      'dash.my_referrals': '我的推荐记录', 'dash.current_promotion': '当前优惠活动',
      'dash.promo_text': '分享您的推荐码——您将获得 <strong style="color:var(--gold);">{referrer}</strong>，好友首次预订可享 <strong style="color:var(--gold);">{referee}</strong> 折扣。',
      'dash.pending_friend': '待确认好友', 'dash.no_referrals': '暂无推荐记录。<br>分享您的推荐码，开始推荐吧！',
      'dash.luckydraw_heading': '幸运<em>抽奖</em>', 'dash.luckydraw_subtitle': '每一笔符合资格的预订或推荐都是一次抽奖机会——请留意查看结果。',
      'dash.my_wins': '我的中奖记录', 'dash.no_wins': '暂无中奖记录——敬请期待！', 'dash.lucky_draw_fallback_name': '幸运抽奖',
      'dash.membership_heading': '我的<em>会员等级</em>', 'dash.membership_subtitle': '您的等级可解锁专属行程与特权。',
      'dash.current_status': '当前状态', 'dash.tier_comparison': '等级比较', 'dash.your_tier': '您的等级',
      'dash.earn_more_premier': '再获 {n} 积分即可升级至尊享', 'dash.earn_more_elite': '再获 {n} 积分即可升级至至尊',
      'dash.highest_tier': '您已达到最高等级 👑', 'dash.member_suffix': '会员',
      'dash.tier_explorer_pts': '0 – 999 积分', 'dash.tier_premier_pts': '1,000 – 4,999 积分', 'dash.tier_elite_pts': '5,000+ 积分',
      'dash.tier_explorer_perk1': '畅享所有探索者行程', 'dash.tier_explorer_perk2': '每消费1令吉获1积分', 'dash.tier_explorer_perk3': '电邮旅行资讯', 'dash.tier_explorer_perk4': '24小时support聊天',
      'dash.tier_premier_perk1': '享有探索者全部权益', 'dash.tier_premier_perk2': '畅享尊享行程', 'dash.tier_premier_perk3': '优先预订通道', 'dash.tier_premier_perk4': '免费旅行保险', 'dash.tier_premier_perk5': '专属会员活动',
      'dash.tier_elite_perk1': '享有尊享全部权益', 'dash.tier_elite_perk2': '畅享至尊专属行程', 'dash.tier_elite_perk3': '专属旅行管家', 'dash.tier_elite_perk4': '机场贵宾室使用权', 'dash.tier_elite_perk5': '年度礼品与惊喜',
      'dash.profile_heading': '我的<em>资料</em>', 'dash.profile_subtitle': '保持资料更新，让预订体验更顺畅。',
      'dash.personal_info': '个人信息',
      'dash.first_name': '名字', 'dash.last_name': '姓氏', 'dash.phone_number': '电话号码',
      'dash.dob': '出生日期', 'dash.nationality': '国籍', 'dash.passport': '护照号码',
      'dash.first_name_ph': 'Jane', 'dash.last_name_ph': 'Smith', 'dash.phone_ph': '+60 12 345 6789', 'dash.nationality_ph': 'Malaysian', 'dash.passport_ph': 'A12345678',
      'dash.save_changes': '保存更改', 'dash.saving': '保存中…', 'dash.profile_saved': '资料已保存 ✓', 'dash.error_prefix': '错误：',
      'dash.modal_book_trip': '预订行程', 'dash.departure_date': '出发日期', 'dash.num_travellers': '旅客人数',
      'dash.special_requests': '特殊要求（可选）', 'dash.special_requests_ph': '饮食需求、无障碍需求等…',
      'dash.estimated_total': '预估总额', 'dash.cancel': '取消',
      'dash.confirm_booking': '确认预订', 'dash.confirming': '确认中…', 'dash.no_dates': '暂无可选日期',
      'dash.select_departure_err': '请选择出发日期。', 'dash.booking_failed': '预订失败：',
      'dash.booking_sent': '预订请求已发送！我们将尽快为您确认 ✈️',
    },

    ms: {
      'tier.explorer': 'Explorer', 'tier.premier': 'Premier', 'tier.elite': 'Elite',
      'status.pending': 'menunggu', 'status.confirmed': 'disahkan', 'status.cancelled': 'dibatalkan', 'status.completed': 'selesai',
      'status.redeemed': 'ditebus', 'status.rewarded': 'diberi ganjaran',
      'journal.chapter_label': 'Bab {word}',
      'journal.chapter_word1': 'Satu', 'journal.chapter_word2': 'Dua', 'journal.chapter_word3': 'Tiga', 'journal.chapter_word4': 'Empat', 'journal.chapter_word5': 'Lima',
      'journal.chapter_word6': 'Enam', 'journal.chapter_word7': 'Tujuh', 'journal.chapter_word8': 'Lapan', 'journal.chapter_word9': 'Sembilan', 'journal.chapter_word10': 'Sepuluh',

      'nav.destinations': 'Destinasi', 'nav.trips': 'Percutian', 'nav.membership': 'Keahlian', 'nav.about': 'Tentang Kami', 'nav.contact': 'Hubungi Kami', 'nav.signin': 'Log Masuk',

      'hero.eyebrow': 'Perjalanan Terancang',
      'hero.heading': 'Mengembara Melangkaui<br>yang <em>Biasa</em>',
      'hero.subtext': 'The Travel Chapter merancang perjalanan luar biasa untuk pengembara yang bercita rasa tinggi — dari ryokan intim di Kyoto hingga sewaan yacht peribadi di Pantai Amalfi.',
      'hero.cta_primary': 'Terokai Percutian',

      'destinations.eyebrow': 'Ke Mana Kami Pergi',
      'destinations.heading': 'Destinasi<br><em>Pilihan</em>',
      'destinations.subtext': 'Setiap destinasi disemak sendiri oleh penyelaras perjalanan kami — dipilih atas kedalaman budaya, keindahan semula jadi dan pengalaman yang jarang ditemui.',
      'journal.toc1': 'Permulaan — Kyoto',
      'journal.toc2': 'Cerita Tersebar Pantas — Amalfi',
      'journal.toc3': 'Belajar Mendengar — Marrakech',
      'journal.toc4': 'Melambatkan Langkah — Luang Prabang',
      'journal.toc5': 'Ke Hujung Dunia — Patagonia',

      'journal.ch1.badge': 'Bab Satu', 'journal.ch1.name': 'Permulaan', 'journal.ch1.region': 'Kyoto, Jepun · 2012',
      'journal.ch1.caption': 'Bermula dengan seorang pengembara, sebuah buku nota, dan perjalanan solo ke Kyoto yang mengubah segalanya — serta janji untuk tidak lagi merancang itinerari yang biasa-biasa sahaja.',
      'journal.ch2.badge': 'Bab Dua', 'journal.ch2.name': 'Cerita Tersebar Pantas', 'journal.ch2.region': 'Pantai Amalfi · 2015',
      'journal.ch2.caption': 'Rakan-rakan yang mendengar tentang perjalanan pertama itu mula meminta bantuan merancang perjalanan mereka sendiri. Menjelang kami menyewa yacht di pantai Itali, kepercayaan telah senyap-senyap menjadi perniagaan kami.',
      'journal.ch3.badge': 'Bab Tiga', 'journal.ch3.name': 'Belajar Mendengar', 'journal.ch3.region': 'Marrakech, Maghribi · 2018',
      'journal.ch3.caption': 'Kami belajar bahawa itinerari terbaik kami tidak pernah ditulis di atas meja — ia datang daripada pemandu tempatan yang tahu lorong mana membawa ke Marrakech yang tiada buku panduan mampu tunjukkan.',
      'journal.ch4.badge': 'Bab Empat', 'journal.ch4.name': 'Melambatkan Langkah', 'journal.ch4.region': 'Luang Prabang, Laos · 2021',
      'journal.ch4.caption': 'Di suatu tempat sepanjang Sungai Mekong ketika subuh, kami memahami erti sebenar perjalanan — bukan menconteng senarai, tetapi berdiri diam cukup lama untuk merasai sesuatu.',
      'journal.ch5.badge': 'Bab Lima', 'journal.ch5.name': 'Ke Hujung Dunia', 'journal.ch5.region': 'Patagonia · 2024',
      'journal.ch5.caption': 'Rasa ingin tahu yang sama telah membawa para pengembara kami ke glasier Patagonia dan lebih jauh lagi — bukti bahawa selepas sedekad, kami masih mengejar rasa pertama di Kyoto itu.',

      'journal.epilogue_eyebrow': 'Epilog',
      'journal.epilogue_heading': 'Bab anda bermula di sini',
      'journal.stat1_lbl': 'Destinasi', 'journal.stat2_lbl': 'Pengembara Gembira', 'journal.stat3_lbl': 'Tahun Pengalaman',

      'manifesto.text': 'Kami percaya perjalanan harus menggerakkan jiwa anda, bukan sekadar membawa anda ke suatu tempat. Setiap bab yang kami cipta mengubah jarak menjadi kenangan — dan kenangan menjadi cerita yang anda bawa pulang.',

      'trips.eyebrow': 'Perjalanan Kami',
      'trips.heading': 'Percutian <em>Pilihan</em>',
      'trips.subtext': 'Setiap perjalanan dirancang dengan teliti — pemandu pakar, kumpulan kecil dan akses kepada pengalaman yang tidak ditawarkan agensi pelancongan biasa.',
      'trips.book_now': 'Tempah Sekarang', 'trips.per_person': '/ seorang', 'trips.max': 'Maks', 'trips.days': 'hari', 'trips.from': 'Dari',
      'trips.card1.name': 'Kyoto Musim Luruh', 'trips.card1.desc': 'Kejar daun maple merah menyala di kuil-kuil terbaik dan taman tersembunyi Kyoto.', 'trips.card1.duration': '8 hari', 'trips.card1.pax': 'Maks 10', 'trips.card1.window': 'Okt – Nov',
      'trips.card2.name': 'Amalfi dengan Yacht', 'trips.card2.desc': 'Perjalanan yacht peribadi di sepanjang Pantai Amalfi — teluk tersembunyi, makanan laut segar dan senja keemasan.', 'trips.card2.duration': '6 hari', 'trips.card2.pax': 'Maks 8', 'trips.card2.window': 'Jun – Jul',
      'trips.card3.name': 'Marrakech & Sekitarnya', 'trips.card3.desc': 'Bandar diraja, khemah gurun Sahara dan perkampungan Pergunungan Atlas — Maghribi secara mendalam.', 'trips.card3.duration': '9 hari', 'trips.card3.pax': 'Maks 14', 'trips.card3.window': 'Sep – Okt',
      'trips.card4.name': 'Perjalanan Sungai Mekong', 'trips.card4.desc': 'Bercuti perlahan di Laos menaiki kapal sungai yang dipulihkan — kuil, pasar dan pagi berkabus.', 'trips.card4.duration': '10 hari', 'trips.card4.pax': 'Maks 12', 'trips.card4.window': 'Nov – Jan',
      'trips.card5.name': 'Keliaran Patagonia', 'trips.card5.desc': 'Mendaki Litar W bersama pemandu gunung pakar — glasier, menara granit dan hujung dunia.', 'trips.card5.duration': '12 hari', 'trips.card5.pax': 'Maks 8', 'trips.card5.window': 'Dis – Feb',
      'trips.card6.name': 'Rendaman Elite Jepun', 'trips.card6.desc': 'Jamuan geisha peribadi, perjalanan keretapi laju dan onsen eksklusif — Jepun pada momen paling intim.', 'trips.card6.duration': '14 hari', 'trips.card6.pax': 'Maks 6', 'trips.card6.window': 'Okt · Mac',

      'membership.eyebrow': 'Keahlian',
      'membership.heading': 'Pilih <em>Bab</em> Anda',
      'membership.subtext': 'Setiap ahli bermula sebagai Explorer dan memperoleh mata ganjaran pada setiap perjalanan — membuka pengalaman lebih kaya semakin kerap anda mengembara.',
      'membership.most_popular': 'Paling Popular',
      'membership.explorer.pts': '0 – 999 Mata', 'membership.premier.pts': '1,000 – 4,999 Mata', 'membership.elite.pts': '5,000+ Mata',
      'membership.explorer.perk1': 'Akses ke semua percutian Explorer', 'membership.explorer.perk2': '1 mata bagi setiap RM dibelanjakan', 'membership.explorer.perk3': 'Kemas kini perjalanan melalui e-mel', 'membership.explorer.perk4': 'Sokongan ahli 24/7',
      'membership.premier.perk1': 'Semua faedah Explorer', 'membership.premier.perk2': 'Akses ke percutian Premier', 'membership.premier.perk3': 'Tempoh tempahan keutamaan', 'membership.premier.perk4': 'Insurans perjalanan percuma', 'membership.premier.perk5': 'Acara eksklusif ahli',
      'membership.elite.perk1': 'Semua faedah Premier', 'membership.elite.perk2': 'Akses ke percutian khas Elite', 'membership.elite.perk3': 'Konsierj perjalanan peribadi', 'membership.elite.perk4': 'Akses lounge lapangan terbang', 'membership.elite.perk5': 'Hadiah & kejutan tahunan',

      'about.eyebrow': 'Kisah Kami',
      'about.heading': 'Mengembara dengan<br><em>Tujuan</em>',
      'about.badge_val': '12+', 'about.badge_lbl': 'Tahun merancang<br>perjalanan',
      'about.p1': 'The Travel Chapter lahir daripada kepercayaan mudah — bahawa perjalanan sepatutnya lebih daripada sekadar senarai semak. Ia harus mengubah anda, menghubungkan anda, dan membuatkan anda dahagakan lebih.',
      'about.p2': 'Kami adalah sekumpulan pengembara bersemangat yang telah menghabiskan lebih sedekad membina hubungan dengan pemandu tempatan, penginapan butik dan pakar budaya di seluruh dunia.',
      'about.p3': 'Setiap itinerari yang kami cipta adalah satu bab dalam cerita anda — ditulis dengan teliti, berirama indah dan mustahil dilupakan.',
      'about.value1.title': 'Utamakan Tempatan', 'about.value1.desc': 'Kami bekerjasama dengan pemandu dan komuniti tempatan di setiap destinasi.',
      'about.value2.title': 'Kualiti Terpilih', 'about.value2.desc': 'Setiap hotel, pemandu dan pengalaman disemak sendiri oleh pasukan kami.',
      'about.value3.title': 'Bertanggungjawab', 'about.value3.desc': 'Kami mengembara dengan penuh keprihatinan — terhadap manusia, budaya dan alam sekitar.',
      'about.value4.title': 'Sentiasa Bersama', 'about.value4.desc': 'Dari tempahan hingga pulang, pasukan kami bersama anda pada setiap langkah.',

      'testimonials.eyebrow': 'Kisah Pengembara',
      'testimonials.heading': 'Apa Kata <em>Ahli Kami</em>',
      'testimonials.card1.text': '"Kyoto pada musim luruh adalah segalanya yang saya bayangkan dan lebih lagi. Akses ke kuil peribadi pada subuh adalah sesuatu yang saya tidak mampu aturkan sendiri."',
      'testimonials.card1.trip': 'Kyoto Musim Luruh · Ahli Premier',
      'testimonials.card2.text': '"Perjalanan yacht Amalfi melangkaui jangkaan saya. Bangun di teluk tersembunyi setiap pagi — sungguh sempurna. Sudah menempah percutian seterusnya."',
      'testimonials.card2.trip': 'Amalfi dengan Yacht · Ahli Elite',
      'testimonials.card3.text': '"The Travel Chapter bukan sekadar merancang percutian — mereka mencipta pengalaman. Perjalanan Sungai Mekong saya terasa seperti mimpi yang saya tidak mahu ia berakhir."',
      'testimonials.card3.trip': 'Perjalanan Sungai Mekong · Ahli Explorer',

      'cta.heading': 'Bersedia Memulakan <em>Bab</em> Anda?',
      'cta.subtext': 'Sertai ribuan pengembara bercita rasa tinggi yang telah mempercayakan kami dengan perjalanan paling berharga mereka.',
      'cta.primary': 'Hubungi Kami',

      'contact.eyebrow': 'Hubungi Kami',
      'contact.heading': 'Mari Rancang<br><em>Perjalanan</em> Anda',
      'contact.subtext': 'Sudah ada destinasi dalam fikiran? Ingin tahu lebih lanjut tentang keahlian kami? Pasukan kami sedia membantu anda mencari percutian yang sempurna.',
      'contact.email_label': 'E-mel Kami', 'contact.phone_label': 'Hubungi Kami', 'contact.address_label': 'Lawati Kami',
      'contact.address_value': 'Kuala Lumpur, Malaysia',
      'contact.form.first_name': 'Nama Pertama', 'contact.form.last_name': 'Nama Akhir', 'contact.form.email': 'Alamat E-mel',
      'contact.form.interested': 'Berminat Dengan', 'contact.form.select_placeholder': 'Pilih destinasi atau percutian…',
      'contact.form.message': 'Mesej Anda', 'contact.form.message_placeholder': 'Ceritakan tentang percutian impian anda…',
      'contact.form.submit': 'Hantar Mesej', 'contact.form.custom_option': 'Lain-lain / Tersuai',
      'contact.form.first_name_ph': 'Jane', 'contact.form.last_name_ph': 'Smith', 'contact.form.email_ph': 'jane@example.com',

      'footer.tagline': 'Merancang perjalanan luar biasa untuk pengembara bercita rasa tinggi sejak 2012. Berpangkalan di Kuala Lumpur, mengembara ke seluruh dunia.',
      'footer.explore_title': 'Terokai', 'footer.members_title': 'Ahli', 'footer.contact_title': 'Hubungi',
      'footer.link_destinations': 'Destinasi', 'footer.link_trips': 'Percutian Pilihan', 'footer.link_membership': 'Keahlian', 'footer.link_about': 'Kisah Kami',
      'footer.link_signin': 'Log Masuk', 'footer.link_dashboard': 'Papan Pemuka', 'footer.link_message': 'Hantar Mesej',
      'footer.copyright': '© 2026 The Travel Chapter. Hak cipta terpelihara.',
      'footer.location': 'Dibina dengan teliti di Kuala Lumpur 🇲🇾',

      'install.title': 'Pasang The Travel Chapter',
      'install.subtext': 'Tambah ke skrin utama untuk akses skrin penuh yang pantas.',
      'install.button': 'Pasang', 'install.dismiss_aria': 'Tutup',
      'install.ios_subtext': 'Ketik Kongsi, kemudian "Tambah ke Skrin Utama" untuk akses skrin penuh yang pantas.',

      'toast.contact_sent': 'Mesej dihantar! Kami akan menghubungi anda dalam masa 24 jam ✓',

      'login.back_to_website': 'Kembali ke Laman Web',
      'login.hero_eyebrow': 'Portal Ahli',
      'login.hero_heading': 'Perjalanan Anda<br>Bermula <em>Di Sini</em>',
      'login.hero_subtext': 'Log masuk untuk mengakses tempahan anda, terokai percutian pilihan, dan urus keahlian anda — semuanya di satu tempat.',
      'login.explore_destinations': 'Terokai Destinasi', 'login.our_story': 'Kisah Kami',
      'login.brand_sub': 'Portal Ahli',
      'login.tab_signin': 'Log Masuk', 'login.tab_register': 'Sertai Kami',
      'login.phone_label': 'Nombor Telefon', 'login.password_label': 'Kata Laluan',
      'login.phone_placeholder': '12 345 6789', 'login.password_placeholder': '••••••••',
      'login.forgot_link': 'Lupa kata laluan?',
      'login.signin_button': 'Log Masuk', 'login.signin_loading': 'Sedang log masuk…',
      'login.new_here': 'Baru di sini?', 'login.create_account_link': 'Cipta akaun',
      'login.send_code_button': 'Hantar Kod Pengesahan',
      'login.finish_profile_label': 'Telefon telah disahkan. Hanya beberapa butiran lagi untuk melengkapkan akaun anda.',
      'login.first_name_label': 'Nama Pertama', 'login.last_name_label': 'Nama Akhir',
      'login.first_name_placeholder': 'Jane', 'login.last_name_placeholder': 'Smith',
      'login.email_label': 'E-mel', 'login.email_placeholder': 'jane@example.com',
      'login.reg_password_placeholder': 'Minimum 8 aksara',
      'login.create_account_button': 'Cipta Akaun', 'login.creating_loading': 'Mencipta akaun…',
      'login.already_member': 'Sudah menjadi ahli?', 'login.signin_link': 'Log masuk',
      'login.verify_default_label': 'Kami telah menghantar kod SMS ke telefon anda.',
      'login.verify_sent': 'Kami telah menghantar kod SMS ke {phone}.',
      'login.verify_code_label': 'Kod Pengesahan', 'login.code_placeholder': 'Kod 6 digit',
      'login.verify_button': 'Sahkan & Teruskan', 'login.verifying_loading': 'Mengesahkan…',
      'login.resend_code': 'Hantar semula kod', 'login.resend_code_cooldown': 'Hantar semula kod ({secs}s)',
      'login.wrong_number': 'Nombor salah?',
      'login.forgot_send_button': 'Hantar Kod SMS', 'login.sending_loading': 'Menghantar…',
      'login.back_to_signin': 'Kembali ke log masuk',
      'login.forgot_verify_default_label': 'Masukkan kod yang kami hantar melalui SMS.',
      'login.forgot_verify_sent': 'Masukkan kod yang kami hantar ke {phone} melalui SMS.',
      'login.new_password_label': 'Kata Laluan Baharu',
      'login.reset_button': 'Tetapkan Semula Kata Laluan', 'login.resetting_loading': 'Menetapkan semula…',
      'login.err_fill_fields': 'Sila isi semua ruangan.',
      'login.err_invalid_phone': 'Masukkan nombor telefon dengan kod negara, contohnya +6591234567.',
      'login.err_fill_required': 'Sila isi semua ruangan yang diperlukan.',
      'login.err_invalid_email': 'Masukkan alamat e-mel yang sah.',
      'login.err_password_length': 'Kata laluan mesti sekurang-kurangnya 8 aksara.',
      'login.err_enter_code': 'Masukkan kod yang dihantar melalui SMS.',
      'login.err_fill_code_password': 'Masukkan kod dan kata laluan baharu anda.',
      'login.err_admin_account': 'Ini adalah akaun admin/staf — sila log masuk di portal admin.',
      'login.toast_welcome': 'Selamat datang ke The Travel Chapter!',
      'login.toast_code_resent': 'Kod dihantar semula melalui SMS.',
      'login.toast_password_updated': 'Kata laluan dikemas kini — melog masuk anda…',

      'dash.tagline': 'Portal Ahli', 'dash.loading': 'Memuatkan…', 'dash.signout': 'Log Keluar',
      'dash.nav_overview': 'Ringkasan', 'dash.nav_trips': 'Terokai Percutian', 'dash.nav_bookings': 'Tempahan Saya',
      'dash.nav_referrals': 'Rujukan', 'dash.nav_luckydraw': 'Cabutan Bertuah', 'dash.nav_membership': 'Keahlian', 'dash.nav_profile': 'Profil Saya',
      'dash.overview_welcome': 'Selamat kembali,', 'dash.overview_subtitle': 'Berikut ringkasan perjalanan anda bersama kami.',
      'dash.stat_bookings': 'Jumlah Tempahan', 'dash.stat_points': 'Mata Tahap', 'dash.stat_tier': 'Tahap Keahlian',
      'dash.recent_bookings': 'Tempahan Terkini', 'dash.tier_progress': 'Kemajuan Tahap',
      'dash.no_bookings_overview': 'Belum ada tempahan.<br>Terokai percutian untuk bermula!',
      'dash.pts_to_premier': '{n} mata lagi ke Premier', 'dash.pts_to_elite': '{n} mata lagi ke Elite',
      'dash.max_tier': 'Tahap tertinggi dicapai 👑', 'dash.pts_suffix': 'mata',
      'dash.browse_heading': 'Terokai <em>Percutian</em>', 'dash.browse_subtitle': 'Temui perjalanan pilihan yang sepadan dengan tahap keahlian anda.',
      'dash.loading_trips': 'Memuatkan percutian…', 'dash.no_trips': 'Tiada percutian tersedia buat masa ini.',
      'dash.book_now': 'Tempah Sekarang', 'dash.locked_suffix': 'sahaja', 'dash.max_label': 'Maks', 'dash.days_label': 'hari', 'dash.per_person': '/ seorang',
      'dash.bookings_heading': 'Tempahan <em>Saya</em>', 'dash.bookings_subtitle': 'Jejak semua perjalanan lepas dan akan datang anda.',
      'dash.no_bookings': 'Belum ada tempahan.<br>Pergi ke Terokai Percutian untuk rancang perjalanan pertama anda!',
      'dash.traveller_singular': 'pengembara', 'dash.traveller_plural': 'pengembara',
      'dash.referrals_heading': 'Rujukan <em>Saya</em>', 'dash.referrals_subtitle': 'Kongsi kod anda dengan rakan — kedua-dua pihak mendapat ganjaran apabila mereka menempah.',
      'dash.your_code': 'Kod Rujukan Anda', 'dash.copy_code': '📋 Salin Kod',
      'dash.code_copied': 'Kod {code} disalin ✓', 'dash.copy_failed': 'Tidak dapat menyalin — sila salin secara manual.',
      'dash.my_referrals': 'Rujukan Saya', 'dash.current_promotion': 'Promosi Semasa',
      'dash.promo_text': 'Kongsi kod anda — anda memperoleh <strong style="color:var(--gold);">{referrer}</strong>, rakan anda mendapat <strong style="color:var(--gold);">{referee}</strong> diskaun untuk percutian pertama mereka.',
      'dash.pending_friend': 'Rakan belum disahkan', 'dash.no_referrals': 'Belum ada rujukan.<br>Kongsi kod anda untuk bermula!',
      'dash.luckydraw_heading': 'Cabutan <em>Bertuah</em>', 'dash.luckydraw_subtitle': 'Setiap tempahan atau rujukan yang layak adalah satu penyertaan — semak di sini untuk keputusan.',
      'dash.my_wins': 'Kemenangan Saya', 'dash.no_wins': 'Belum ada kemenangan — nantikan!', 'dash.lucky_draw_fallback_name': 'Cabutan Bertuah',
      'dash.membership_heading': 'Keahlian <em>Saya</em>', 'dash.membership_subtitle': 'Tahap anda membuka percutian dan keistimewaan eksklusif.',
      'dash.current_status': 'Status Semasa', 'dash.tier_comparison': 'Perbandingan Tahap', 'dash.your_tier': 'Tahap Anda',
      'dash.earn_more_premier': 'Perolehi {n} mata lagi untuk capai Premier', 'dash.earn_more_elite': 'Perolehi {n} mata lagi untuk capai Elite',
      'dash.highest_tier': 'Anda telah mencapai tahap tertinggi kami 👑', 'dash.member_suffix': 'Ahli',
      'dash.tier_explorer_pts': '0 – 999 mata', 'dash.tier_premier_pts': '1,000 – 4,999 mata', 'dash.tier_elite_pts': '5,000+ mata',
      'dash.tier_explorer_perk1': 'Akses ke semua percutian Explorer', 'dash.tier_explorer_perk2': '1 mata bagi setiap RM dibelanjakan', 'dash.tier_explorer_perk3': 'Kemas kini perjalanan melalui e-mel', 'dash.tier_explorer_perk4': 'Sembang sokongan 24/7',
      'dash.tier_premier_perk1': 'Semua faedah Explorer', 'dash.tier_premier_perk2': 'Akses ke percutian Premier', 'dash.tier_premier_perk3': 'Tempoh tempahan keutamaan', 'dash.tier_premier_perk4': 'Insurans perjalanan percuma', 'dash.tier_premier_perk5': 'Acara eksklusif ahli',
      'dash.tier_elite_perk1': 'Semua faedah Premier', 'dash.tier_elite_perk2': 'Akses ke percutian khas Elite', 'dash.tier_elite_perk3': 'Konsierj perjalanan peribadi', 'dash.tier_elite_perk4': 'Akses lounge lapangan terbang', 'dash.tier_elite_perk5': 'Hadiah & kejutan tahunan',
      'dash.profile_heading': 'Profil <em>Saya</em>', 'dash.profile_subtitle': 'Pastikan maklumat anda terkini untuk pengalaman tempahan yang lancar.',
      'dash.personal_info': 'Maklumat Peribadi',
      'dash.first_name': 'Nama Pertama', 'dash.last_name': 'Nama Akhir', 'dash.phone_number': 'Nombor Telefon',
      'dash.dob': 'Tarikh Lahir', 'dash.nationality': 'Kewarganegaraan', 'dash.passport': 'Nombor Pasport',
      'dash.first_name_ph': 'Jane', 'dash.last_name_ph': 'Smith', 'dash.phone_ph': '+60 12 345 6789', 'dash.nationality_ph': 'Malaysian', 'dash.passport_ph': 'A12345678',
      'dash.save_changes': 'Simpan Perubahan', 'dash.saving': 'Menyimpan…', 'dash.profile_saved': 'Profil disimpan ✓', 'dash.error_prefix': 'Ralat: ',
      'dash.modal_book_trip': 'Tempah Percutian', 'dash.departure_date': 'Tarikh Berlepas', 'dash.num_travellers': 'Bilangan Pengembara',
      'dash.special_requests': 'Permintaan Khas (pilihan)', 'dash.special_requests_ph': 'Keperluan pemakanan, keperluan kemudahan…',
      'dash.estimated_total': 'Anggaran Jumlah', 'dash.cancel': 'Batal',
      'dash.confirm_booking': 'Sahkan Tempahan', 'dash.confirming': 'Mengesahkan…', 'dash.no_dates': 'Tiada tarikh tersedia',
      'dash.select_departure_err': 'Sila pilih tarikh berlepas.', 'dash.booking_failed': 'Tempahan gagal: ',
      'dash.booking_sent': 'Permintaan tempahan dihantar! Kami akan mengesahkan tidak lama lagi ✈️',
    },
  };

  function detectLang() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved && SUPPORTED.includes(saved)) return saved;
    } catch (e) {}
    const nav = ((global.navigator && (navigator.language || navigator.userLanguage)) || 'en').toLowerCase();
    if (nav.startsWith('zh')) return 'zh';
    if (nav.startsWith('ms')) return 'ms';
    return 'en';
  }

  let currentLang = detectLang();
  const listeners = [];

  function t(key, vars) {
    let str = (DICT[currentLang] && DICT[currentLang][key]);
    if (str === undefined) str = (DICT.en && DICT.en[key]);
    if (str === undefined) return key;
    if (vars) {
      Object.keys(vars).forEach(k => { str = str.split('{' + k + '}').join(vars[k]); });
    }
    return str;
  }

  function applyStatic(root) {
    root = root || document;
    root.querySelectorAll('[data-i18n]').forEach(el => {
      const key = el.getAttribute('data-i18n');
      const val = t(key);
      if (el.hasAttribute('data-i18n-html')) el.innerHTML = val; else el.textContent = val;
    });
    root.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
      el.setAttribute('placeholder', t(el.getAttribute('data-i18n-placeholder')));
    });
    root.querySelectorAll('[data-i18n-aria-label]').forEach(el => {
      el.setAttribute('aria-label', t(el.getAttribute('data-i18n-aria-label')));
    });
    document.documentElement.setAttribute('lang', currentLang === 'zh' ? 'zh-CN' : currentLang);
    root.querySelectorAll('.lang-btn').forEach(b => b.classList.toggle('active', b.getAttribute('data-lang') === currentLang));
  }

  function setLang(lang) {
    if (!SUPPORTED.includes(lang) || lang === currentLang) return;
    currentLang = lang;
    try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) {}
    applyStatic();
    listeners.forEach(fn => { try { fn(lang); } catch (e) { console.error(e); } });
  }

  function onChange(fn) { listeners.push(fn); }

  // Delegated click handler so any page just needs elements like
  // <button class="lang-btn" data-lang="zh">中文</button>
  document.addEventListener('click', function (e) {
    const btn = e.target.closest('[data-lang]');
    if (btn) setLang(btn.getAttribute('data-lang'));
  });

  document.addEventListener('DOMContentLoaded', function () { applyStatic(); });

  global.TC_I18N = {
    t, setLang, applyStatic, onChange,
    get lang() { return currentLang; },
    SUPPORTED,
  };
})(window);
