//
//  BundledArticles.swift
//  Prism
//

import Foundation

/// The library that ships in the app. Twelve Soma pieces lead, then the NIH
/// News in Health and NIH Research Matters library in `ExploreLibrary.json`.
/// General wellness reading only: no piece names Soma's hardware, and none
/// diagnoses, treats or promises an outcome; each lists the published work
/// it rests on.
enum BundledArticles {
    static let all: [Article] = (featured + nihLibrary).sorted { $0.publishedAt > $1.publishedAt }

    /// The original Soma set, kept as named handles other pages still link to.
    private static let featured: [Article] = [
        sleepRegularity, heartRateVariability, restingHeartRate, zoneTwo, cardioFitness, daylight,
        caffeine, alcohol, strength, breathing, deepSleep, protein,
    ]

    /// NIH pieces decoded from the bundled JSON. A missing or unreadable file
    /// leaves Explore on the twelve featured articles rather than crashing.
    private static let nihLibrary: [Article] = {
        guard let url = Bundle.main.url(forResource: "ExploreLibrary", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Article].self, from: data)) ?? []
    }()

    static func article(slug: String) -> Article? {
        all.first { $0.slug == slug }
    }

    private static func day(_ text: String) -> Date {
        (try? Date.ISO8601FormatStyle().year().month().day().parse(text)) ?? Date(timeIntervalSince1970: 0)
    }

    /// The cover of each piece, from Unsplash (free to use under the Unsplash
    /// licence, commercial use included), saved at 1200 px wide in
    /// `Assets.xcassets/Articles/<slug>`. The licence asks for no credit, and
    /// the reader gives one anyway.
    private static let photos: [String: (name: String, id: String)] = [
        "sleep-regularity": ("Suhas Hanjar", "PgROW5b4Sw0"),
        "deep-sleep": ("Quentin Schulz", "7_jpPTmV65E"),
        "daylight-and-your-body-clock": ("Hoover Tung", "DjlNzHuv_Ck"),
        "hrv-basics": ("Ryan Stone", "jV2cNlH4e6A"),
        "alcohol-and-sleep": ("Denis Sousa", "PzZnixZv12U"),
        "resting-heart-rate-trends": ("Giana Bleu", "fnQ_Zk9TQQg"),
        "zone-2-training": ("Viktor Bystrov", "Gi0OMNguFaw"),
        "vo2-max-and-longevity": ("Alban Rozes", "DhGC1dVw0Tg"),
        "strength-and-lean-mass": ("Alora Griffiths", "hvFrA-iKQd0"),
        "caffeine-timing": ("Dani", "ZLqxSzvVr7I"),
        "protein-and-muscle": ("Shelley Pauls", "t4X660oKiYs"),
        "breathing-and-stress": ("Ant Rozetsky", "q-DJ9XhKkhA"),
    ]

    private static func photo(_ slug: String) -> ArticlePhoto? {
        guard let photo = photos[slug] else { return nil }
        return ArticlePhoto(asset: "Articles/\(slug)", credit: photo.name,
                            url: URL(string: "https://unsplash.com/photos/\(photo.id)"), library: "Unsplash")
    }

    private static func cite(_ title: String, _ publisher: String, _ address: String) -> ArticleCitation {
        ArticleCitation(title: title, publisher: publisher, url: URL(string: address))
    }

    // MARK: Sleep

    static let sleepRegularity = Article(
        id: "bundled-sleep-regularity", slug: "sleep-regularity",
        title: "Why a steady bedtime matters",
        subtitle: "Regular nights may count as much as long ones.",
        topic: .sleep, minutes: 4, coverImageURL: nil,
        body: """
        Most sleep advice is about how long you sleep. A growing body of research looks at something simpler: whether you go to bed and get up at about the same times each day.

        ## What regularity means

        Researchers often score it as the chance that you are in the same state, asleep or awake, at the same clock time on two consecutive days. A late Friday and a long Sunday lie in both lower it, even when the weekly total looks fine.

        ## What the research has found

        In a large UK Biobank study, people with the most regular sleep had lower all cause mortality over several years than people with the least regular sleep, and regularity was a stronger predictor than duration. Earlier work in students linked irregular schedules with later body clocks and lower grades. These are associations, not proof that changing your schedule changes your outcome, but they point the same way.

        ## Easy things to try

        - Pick a wake time you can keep on most days, weekends included, within about an hour.
        - Let bedtime follow: go to bed when you are sleepy, not by forcing it early.
        - Get outside light soon after waking to anchor the day.
        - Adults generally need at least seven hours; regularity works alongside that, not instead of it.
        """,
        publishedAt: day("2026-09-30"),
        sources: [
            cite("Sleep regularity is a stronger predictor of mortality risk than sleep duration", "Windred et al., Sleep, 2024",
                 "https://doi.org/10.1093/sleep/zsad253"),
            cite("Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing",
                 "Phillips et al., Scientific Reports, 2017", "https://doi.org/10.1038/s41598-017-03171-4"),
            cite("Recommended amount of sleep for a healthy adult", "Watson et al., AASM and SRS consensus, Sleep, 2015",
                 "https://doi.org/10.5665/sleep.4716"),
        ],
        photo: photo("sleep-regularity"))

    static let deepSleep = Article(
        id: "bundled-deep-sleep", slug: "deep-sleep",
        title: "Why deep sleep comes first",
        subtitle: "The early hours of the night carry most of it.",
        topic: .sleep, minutes: 3, coverImageURL: nil,
        body: """
        A night of sleep is not one even state. It cycles through light sleep, deep (slow wave) sleep and REM sleep roughly every 90 minutes, and the mix changes as the night goes on.

        ## Front loaded

        Deep sleep is concentrated in the first cycles. REM sleep grows longer toward morning. That is why a short night that cuts off the end mostly costs REM, while a late, broken start can cost deep sleep.

        ## What deep sleep is for

        During slow wave sleep the brain's electrical activity slows into large, synchronised waves, heart rate and breathing settle, and growth hormone is released. In mice, sleep increases the flow of fluid that clears waste from the brain; how far that carries over to people is still being studied.

        ## It changes with age

        Deep sleep declines steadily across adulthood. Less of it at 60 than at 25 is expected, not a sign that something is wrong.

        ## Protecting the early night

        - Keep alcohol and heavy meals away from bedtime; both can disturb the first cycles.
        - A cool, dark, quiet room helps you stay down once you are asleep.
        - A regular schedule gives the first cycles their best chance.
        """,
        publishedAt: day("2026-09-18"),
        sources: [
            cite("Brain Basics: Understanding Sleep", "National Institute of Neurological Disorders and Stroke",
                 "https://www.ninds.nih.gov/health-information/public-education/brain-basics/brain-basics-understanding-sleep"),
            cite("Meta-analysis of quantitative sleep parameters from childhood to old age in healthy individuals",
                 "Ohayon et al., Sleep, 2004", "https://doi.org/10.1093/sleep/27.7.1255"),
            cite("Sleep drives metabolite clearance from the adult brain", "Xie et al., Science, 2013",
                 "https://doi.org/10.1126/science.1241224"),
        ],
        photo: photo("deep-sleep"))

    static let daylight = Article(
        id: "bundled-daylight", slug: "daylight-and-your-body-clock",
        title: "Daylight sets your body clock",
        subtitle: "Bright mornings, dim evenings.",
        topic: .sleep, minutes: 4, coverImageURL: nil,
        body: """
        Your body runs on a clock of a little over 24 hours. Light reaching the eyes is the main signal that keeps it lined up with the day, through cells in the retina that respond most to bright, blue rich light.

        ## Timing is everything

        Light in the morning tends to move the clock earlier, making it easier to feel sleepy at night and alert in the morning. Bright light late in the evening tends to push it later. The same lamp has opposite effects depending on when you see it.

        ## Outdoors is much brighter

        Even an overcast day outdoors is many times brighter than a typical office. In one study, a week of camping with only natural light shifted people's internal clocks about two hours earlier and lined them up more closely with sunrise and sunset.

        ## A simple light diet

        Expert recommendations published in 2022 suggest:

        - During the day, aim for bright light, ideally outdoors, especially in the morning.
        - In the three hours before bed, keep light dim and warm.
        - While sleeping, keep the room as dark as you can.

        A short walk outside within an hour or two of waking is one of the easiest ways to follow all three.
        """,
        publishedAt: day("2026-09-10"),
        sources: [
            cite("Recommendations for daytime, evening, and nighttime indoor light exposure to best support physiology, sleep, and wakefulness in healthy adults",
                 "Brown et al., PLOS Biology, 2022", "https://doi.org/10.1371/journal.pbio.3001571"),
            cite("Entrainment of the human circadian clock to the natural light-dark cycle", "Wright et al., Current Biology, 2013",
                 "https://doi.org/10.1016/j.cub.2013.06.039"),
            cite("Effects of light on human circadian rhythms, sleep and mood", "Blume, Garbazza and Spitschan, Somnologie, 2019",
                 "https://doi.org/10.1007/s11818-019-00215-x"),
        ],
        photo: photo("daylight-and-your-body-clock"))

    // MARK: Recovery

    static let heartRateVariability = Article(
        id: "bundled-hrv-basics", slug: "hrv-basics",
        title: "What your HRV is telling you",
        subtitle: "The small swings between heartbeats.",
        topic: .recovery, minutes: 4, coverImageURL: nil,
        body: """
        Your heart does not beat like a metronome. The time between beats shifts by a few milliseconds from one beat to the next, speeding up slightly as you breathe in and slowing as you breathe out. Heart rate variability, or HRV, measures that variation.

        ## Why it moves

        HRV reflects, in part, the balance of the nervous system that runs in the background. Rest, good sleep and fitness tend to go with higher values; hard training, short sleep, alcohol, illness and stress tend to lower it for a while.

        ## Your own baseline matters most

        HRV differs widely between people, and falls with age, so comparing your number with someone else's says little. What is useful is how today compares with your own usual range. Studies of endurance athletes find that a rolling weekly average is more informative than any single morning.

        ## Reading it well

        - Measure the same way each time; overnight or just after waking is most consistent.
        - Look at the trend over a week, not the day to day jumps.
        - A dip after a hard day is normal and usually recovers.
        - Different devices compute HRV differently (RMSSD and SDNN, for example), so stick to one.

        HRV is one signal among many. Use it alongside how you feel, not instead of it.
        """,
        publishedAt: day("2026-09-28"),
        sources: [
            cite("An Overview of Heart Rate Variability Metrics and Norms", "Shaffer and Ginsberg, Frontiers in Public Health, 2017",
                 "https://doi.org/10.3389/fpubh.2017.00258"),
            cite("Heart rate variability: standards of measurement, physiological interpretation and clinical use",
                 "Task Force of the ESC and NASPE, Circulation, 1996", "https://doi.org/10.1161/01.CIR.93.5.1043"),
            cite("Training adaptation and heart rate variability in elite endurance athletes", "Plews et al., Sports Medicine, 2013",
                 "https://doi.org/10.1007/s40279-013-0071-8"),
        ],
        photo: photo("hrv-basics"))

    static let alcohol = Article(
        id: "bundled-alcohol-and-sleep", slug: "alcohol-and-sleep",
        title: "Alcohol and your night",
        subtitle: "Easier to fall asleep, harder to rest.",
        topic: .recovery, minutes: 3, coverImageURL: nil,
        body: """
        A drink in the evening can make it easier to drift off. What happens later in the night is a different story.

        ## The first half and the second half

        Alcohol tends to shorten the time to fall asleep and can increase deep sleep early on. As it is metabolised, sleep becomes lighter and more broken in the second half of the night, and REM sleep is reduced. A review of the research found these effects at every dose studied, growing with the amount.

        ## What it does to the heart overnight

        In a real world study of thousands of people, evening alcohol was linked to a higher heart rate and lower HRV during the first hours of sleep, in a dose dependent way. Even one or two drinks showed a measurable change.

        ## If you drink

        - Leave a few hours between the last drink and bed.
        - Alternate with water.
        - Notice how your sleep and next morning feel after different amounts; your own data is a good guide.
        """,
        publishedAt: day("2026-09-14"),
        sources: [
            cite("Alcohol and sleep I: effects on normal sleep", "Ebrahim et al., Alcoholism: Clinical and Experimental Research, 2013",
                 "https://doi.org/10.1111/acer.12006"),
            cite("Acute effect of alcohol intake on cardiovascular autonomic regulation during the first hours of sleep in a large real-world sample of Finnish employees",
                 "Pietilä et al., JMIR Mental Health, 2018", "https://doi.org/10.2196/mental.9519"),
            cite("Alcohol's Effects on Health", "National Institute on Alcohol Abuse and Alcoholism",
                 "https://www.niaaa.nih.gov/alcohols-effects-health"),
        ],
        photo: photo("alcohol-and-sleep"))

    // MARK: Heart

    static let restingHeartRate = Article(
        id: "bundled-resting-heart-rate", slug: "resting-heart-rate-trends",
        title: "Reading your resting heart rate",
        subtitle: "Watch the trend, not the day.",
        topic: .heart, minutes: 3, coverImageURL: nil,
        body: """
        Resting heart rate is how many times your heart beats per minute when you are calm and still. For most adults it sits somewhere between 60 and 100, and fitter people often sit lower.

        ## Everyone has their own normal

        A study of more than 92,000 people wearing trackers found that average resting heart rate differed by as much as 70 beats per minute between individuals, while each person's own value stayed fairly steady from day to day. That is why your number is best compared with yourself.

        ## What moves it

        - Regular aerobic exercise tends to lower it over weeks and months.
        - Poor sleep, alcohol, heat, dehydration, stress and illness can raise it for a day or a few.
        - It drifts a little with the seasons and with age.

        ## Using the trend

        A gentle downward trend while you train is a common sign of growing fitness. A rise of several beats that lasts for a few days often lines up with a late night, a hard week or a cold coming on, and is a cue to take it easier.

        If your resting heart rate is often well outside the usual range, or you notice symptoms, talk to a clinician.
        """,
        publishedAt: day("2026-09-24"),
        sources: [
            cite("Inter- and intraindividual variability in daily resting heart rate and its associations with age, sex, sleep, BMI, and time of year",
                 "Quer et al., PLOS ONE, 2020", "https://doi.org/10.1371/journal.pone.0227709"),
            cite("All About Heart Rate", "American Heart Association",
                 "https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse"),
        ],
        photo: photo("resting-heart-rate-trends"))

    // MARK: Movement

    static let zoneTwo = Article(
        id: "bundled-zone-2", slug: "zone-2-training",
        title: "Zone 2, the easy pace that builds",
        subtitle: "Slow enough to talk, long enough to count.",
        topic: .movement, minutes: 4, coverImageURL: nil,
        body: """
        Zone 2 is a steady, comfortable effort: you are breathing harder than at rest but can still hold a conversation. On most scales it sits around 60 to 70 percent of maximum heart rate.

        ## Why easy works

        Studies of endurance athletes across sports find a common pattern: around 80 percent of training is done at low intensity, with a smaller share kept genuinely hard. Easy volume builds the aerobic base, including the muscles' ability to burn fat for fuel, without the recovery cost of hard sessions.

        ## Finding your zone

        - The talk test: you can speak in full sentences, but would rather not sing.
        - Breathing through the nose is usually still possible.
        - Heart rate zones from a watch are estimates; let the talk test overrule them.

        ## How much

        The World Health Organization recommends 150 to 300 minutes of moderate activity a week for adults, or 75 to 150 minutes of vigorous activity, or a mix. Brisk walks, easy cycling, swimming and rowing all count. Several sessions of 30 to 60 minutes is a practical way to get there.
        """,
        publishedAt: day("2026-09-22"),
        sources: [
            cite("What is best practice for training intensity and duration distribution in endurance athletes?",
                 "Seiler, International Journal of Sports Physiology and Performance, 2010", "https://doi.org/10.1123/ijspp.5.3.276"),
            cite("Assessment of metabolic flexibility by means of measuring blood lactate, fat, and carbohydrate oxidation responses to exercise",
                 "San-Millán and Brooks, Sports Medicine, 2018", "https://doi.org/10.1007/s40279-017-0751-x"),
            cite("World Health Organization 2020 guidelines on physical activity and sedentary behaviour", "Bull et al., British Journal of Sports Medicine, 2020",
                 "https://doi.org/10.1136/bjsports-2020-102955"),
        ],
        photo: photo("zone-2-training"))

    // MARK: Longevity

    static let cardioFitness = Article(
        id: "bundled-vo2-max", slug: "vo2-max-and-longevity",
        title: "VO₂ max and a long life",
        subtitle: "Fitness is one of the strongest signals we have.",
        topic: .longevity, minutes: 4, coverImageURL: nil,
        body: """
        VO₂ max is the most oxygen your body can take in and use during hard exercise. It is the standard measure of cardiorespiratory fitness, and watches estimate it from your heart rate during walks and runs.

        ## What the research shows

        In a study of more than 120,000 adults who did treadmill tests, higher fitness was associated with lower mortality across every age group, with no upper limit to the benefit. A meta-analysis found that each step up in fitness was linked to lower risk of death and heart disease. The American Heart Association has called for fitness to be treated as a vital sign.

        These are associations in large groups, and fitness travels with other healthy habits. Still, the link is strong and consistent.

        ## It can be trained

        Fitness responds to training at any age. The biggest gains come to people who start from the lowest levels: moving from the least fit group to the next is associated with a large difference.

        - Build a base of steady aerobic exercise most days.
        - Add one session a week of harder intervals, such as four bouts of four minutes at a hard effort with easy recovery between.
        - Expect change over months, and read a watch estimate as a trend rather than a lab result.
        """,
        publishedAt: day("2026-09-26"),
        sources: [
            cite("Association of cardiorespiratory fitness with long-term mortality among adults undergoing exercise treadmill testing",
                 "Mandsager et al., JAMA Network Open, 2018", "https://doi.org/10.1001/jamanetworkopen.2018.3605"),
            cite("Cardiorespiratory fitness as a quantitative predictor of all-cause mortality and cardiovascular events in healthy men and women",
                 "Kodama et al., JAMA, 2009", "https://doi.org/10.1001/jama.2009.681"),
            cite("Importance of assessing cardiorespiratory fitness in clinical practice", "Ross et al., AHA Scientific Statement, Circulation, 2016",
                 "https://doi.org/10.1161/CIR.0000000000000461"),
        ],
        photo: photo("vo2-max-and-longevity"))

    static let strength = Article(
        id: "bundled-strength", slug: "strength-and-lean-mass",
        title: "Strength training keeps you capable",
        subtitle: "Muscle is worth building at every age.",
        topic: .longevity, minutes: 4, coverImageURL: nil,
        body: """
        From middle age onward, people tend to lose muscle mass and strength gradually unless they work to keep it. Over decades that loss can make everyday tasks, like climbing stairs or carrying shopping, harder.

        ## What lifting does

        Resistance training builds and maintains muscle, strength and bone, and is associated with better blood sugar control and a healthier body composition. A meta-analysis of prospective studies found that people who did muscle strengthening activities had a lower risk of death from all causes, with the largest difference at about 30 to 60 minutes a week.

        ## How much

        Global guidelines recommend muscle strengthening activities on two or more days a week, working all the major muscle groups, on top of aerobic activity.

        ## Getting started

        - Squats, push ups, rows, hinges and carries cover most of the body.
        - Pick a load you can lift with good form for 8 to 12 repetitions, leaving one or two in reserve.
        - Add a little load or a few repetitions over time.
        - Bands, body weight and household objects work as well as a gym to begin.
        """,
        publishedAt: day("2026-09-20"),
        sources: [
            cite("Muscle-strengthening activities are associated with lower risk and mortality in major non-communicable diseases",
                 "Momma et al., British Journal of Sports Medicine, 2022", "https://doi.org/10.1136/bjsports-2021-105061"),
            cite("Resistance training is medicine: effects of strength training on health", "Westcott, Current Sports Medicine Reports, 2012",
                 "https://doi.org/10.1249/JSR.0b013e31825dabb8"),
            cite("World Health Organization 2020 guidelines on physical activity and sedentary behaviour", "Bull et al., British Journal of Sports Medicine, 2020",
                 "https://doi.org/10.1136/bjsports-2020-102955"),
        ],
        photo: photo("strength-and-lean-mass"))

    // MARK: Nutrition

    static let caffeine = Article(
        id: "bundled-caffeine-timing", slug: "caffeine-timing",
        title: "When the last coffee still counts",
        subtitle: "Caffeine lingers longer than it feels.",
        topic: .nutrition, minutes: 3, coverImageURL: nil,
        body: """
        Caffeine works by blocking adenosine, a chemical that builds up while you are awake and makes you feel sleepy. It takes several hours for your body to clear half of a dose, and that time varies widely between people.

        ## The afternoon cup

        In a controlled study, 400 mg of caffeine taken six hours before bed still cut total sleep by more than an hour, even though many participants did not notice the difference. A 2023 meta-analysis found caffeine reduced total sleep time and deep sleep, and suggested a cut off of about 8.8 hours before bed for a typical cup of coffee.

        ## How much

        For healthy adults, the US Food and Drug Administration cites 400 mg a day, about four or five cups of brewed coffee, as an amount not generally associated with negative effects. Sensitivity varies, and pregnancy, some medicines and some conditions change the picture.

        ## Easy things to try

        - Move your last caffeinated drink to late morning or early afternoon.
        - Remember tea, cola, energy drinks and chocolate count too.
        - If you sleep poorly, try a week with an earlier cut off and see how it feels.
        """,
        publishedAt: day("2026-09-16"),
        sources: [
            cite("Caffeine effects on sleep taken 0, 3, or 6 hours before going to bed", "Drake et al., Journal of Clinical Sleep Medicine, 2013",
                 "https://doi.org/10.5664/jcsm.3170"),
            cite("The effect of caffeine on subsequent sleep: a systematic review and meta-analysis", "Gardiner et al., Sleep Medicine Reviews, 2023",
                 "https://doi.org/10.1016/j.smrv.2023.101764"),
            cite("Spilling the Beans: How Much Caffeine is Too Much?", "US Food and Drug Administration",
                 "https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much"),
        ],
        photo: photo("caffeine-timing"))

    static let protein = Article(
        id: "bundled-protein", slug: "protein-and-muscle",
        title: "Protein, spread through the day",
        subtitle: "What your muscles need to make the most of training.",
        topic: .nutrition, minutes: 3, coverImageURL: nil,
        body: """
        Protein supplies the building blocks your muscles use to repair and grow after exercise. How much you eat, and how you spread it, can make training go further.

        ## How much

        The standard recommendation for adults is 0.8 g per kilogram of body weight a day. A meta-analysis of resistance training studies found that gains in lean mass levelled off at around 1.6 g per kilogram a day. Expert groups on healthy ageing suggest older adults aim for 1.0 to 1.2 g per kilogram, and more if they are very active.

        ## Spreading it out

        Muscle responds to a meal with a decent serving of protein, around 25 to 30 g for many adults. Many people eat little protein at breakfast and most at dinner; evening out the meals is an easy change.

        ## Good sources

        - Eggs, dairy, fish, poultry and lean meat.
        - Beans, lentils, tofu, tempeh and edamame.
        - Nuts and seeds as a top up.

        If you have kidney disease or another condition that affects your diet, check with a clinician before raising your intake.
        """,
        publishedAt: day("2026-09-12"),
        sources: [
            cite("A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength",
                 "Morton et al., British Journal of Sports Medicine, 2018", "https://doi.org/10.1136/bjsports-2017-097608"),
            cite("Evidence-based recommendations for optimal dietary protein intake in older people: a position paper from the PROT-AGE Study Group",
                 "Bauer et al., Journal of the American Medical Directors Association, 2013", "https://doi.org/10.1016/j.jamda.2013.05.021"),
        ],
        photo: photo("protein-and-muscle"))

    // MARK: Mind

    static let breathing = Article(
        id: "bundled-breathing", slug: "breathing-and-stress",
        title: "Five minutes of slow breathing",
        subtitle: "A long exhale is a quick way to settle.",
        topic: .mind, minutes: 3, coverImageURL: nil,
        body: """
        Breathing is one of the few parts of the body's automatic machinery you can steer on purpose. Slowing it down, especially the exhale, is linked with a calmer state.

        ## What the research suggests

        A systematic review of slow breathing, around six breaths a minute, found it was associated with greater heart rate variability, more relaxation and less anxiety. In a 2023 randomised study, five minutes a day of cyclic sighing, which stresses a long exhale, improved mood and lowered breathing rate at rest more than mindfulness meditation over a month.

        ## Two to try

        - **Cyclic sighing:** breathe in through the nose, take a second short sip of air on top, then let it all out slowly through the mouth. Repeat for five minutes.
        - **Resonant breathing:** in for about five seconds, out for about five seconds, for five to ten minutes.

        Sit comfortably, keep it gentle, and stop if you feel light headed. It is a tool for everyday stress; for stress or anxiety that is persistent or overwhelming, talk to a professional.
        """,
        publishedAt: day("2026-09-08"),
        sources: [
            cite("Brief structured respiration practices enhance mood and reduce physiological arousal", "Balban et al., Cell Reports Medicine, 2023",
                 "https://doi.org/10.1016/j.xcrm.2022.100895"),
            cite("How breath-control can change your life: a systematic review on psycho-physiological correlates of slow breathing",
                 "Zaccaro et al., Frontiers in Human Neuroscience, 2018", "https://doi.org/10.3389/fnhum.2018.00353"),
            cite("Heart rate variability biofeedback: how and why does it work?", "Lehrer and Gevirtz, Frontiers in Psychology, 2014",
                 "https://doi.org/10.3389/fpsyg.2014.00756"),
        ],
        photo: photo("breathing-and-stress"))
}
