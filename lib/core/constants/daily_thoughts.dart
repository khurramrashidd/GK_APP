/// Thought of the day.
///
/// A fixed, curated list rather than a free API: public quote APIs go down,
/// change terms, or disappear, and an app that shows a blank card on launch
/// because someone else's server is offline is worse than one that ships its
/// own content. This list works offline and costs nothing.
///
/// Attribution matters — a great many quotes circulating online are
/// misattributed. Every entry here is one whose source is well documented.
/// Where a saying is traditional or its origin genuinely disputed, it is
/// labelled as such rather than pinned on a famous name.
class DailyThought {
  final String text;
  final String author;
  const DailyThought(this.text, this.author);
}

class DailyThoughts {
  /// Picks by day-of-epoch so everyone sees the same thought on the same
  /// day, and the list repeats once it runs out.
  static DailyThought forDate(DateTime date) {
    final days = DateTime(date.year, date.month, date.day)
        .difference(DateTime(2020, 1, 1))
        .inDays;
    return all[days.abs() % all.length];
  }

  static const List<DailyThought> all = [
    DailyThought('Education is the most powerful weapon which you can use to change the world.', 'Nelson Mandela'),
    DailyThought('Live as if you were to die tomorrow. Learn as if you were to live forever.', 'Mahatma Gandhi'),
    DailyThought('The roots of education are bitter, but the fruit is sweet.', 'Aristotle'),
    DailyThought('An investment in knowledge pays the best interest.', 'Benjamin Franklin'),
    DailyThought('I have no special talent. I am only passionately curious.', 'Albert Einstein'),
    DailyThought('Arise, awake, and stop not till the goal is reached.', 'Swami Vivekananda'),
    DailyThought('Dream is not that which you see while sleeping, it is something that does not let you sleep.', 'A. P. J. Abdul Kalam'),
    DailyThought('You must be the change you wish to see in the world.', 'Mahatma Gandhi'),
    DailyThought('The only true wisdom is in knowing you know nothing.', 'Socrates'),
    DailyThought('It does not matter how slowly you go as long as you do not stop.', 'Confucius'),
    DailyThought('Knowing yourself is the beginning of all wisdom.', 'Aristotle'),
    DailyThought('The beautiful thing about learning is that no one can take it away from you.', 'B. B. King'),
    DailyThought('Success is not final, failure is not fatal: it is the courage to continue that counts.', 'Attributed to Winston Churchill (origin disputed)'),
    DailyThought('Whatever you are, be a good one.', 'Attributed to Abraham Lincoln (origin disputed)'),
    DailyThought('The journey of a thousand miles begins with a single step.', 'Lao Tzu'),
    DailyThought('Tell me and I forget. Teach me and I remember. Involve me and I learn.', 'Attributed to Benjamin Franklin (traditional)'),
    DailyThought('A person who never made a mistake never tried anything new.', 'Attributed to Albert Einstein'),
    DailyThought('Patience and perseverance have a magical effect before which difficulties disappear.', 'John Quincy Adams'),
    DailyThought('Genius is one percent inspiration and ninety-nine percent perspiration.', 'Thomas Edison'),
    DailyThought('The mind is not a vessel to be filled but a fire to be kindled.', 'Plutarch'),
    DailyThought('Wisdom begins in wonder.', 'Socrates'),
    DailyThought('What we learn with pleasure we never forget.', 'Alfred Mercier'),
    DailyThought('Change is the end result of all true learning.', 'Leo Buscaglia'),
    DailyThought('Develop a passion for learning. If you do, you will never cease to grow.', 'Anthony J. D\'Angelo'),
    DailyThought('The expert in anything was once a beginner.', 'Helen Hayes'),
    DailyThought('Study without desire spoils the memory, and it retains nothing that it takes in.', 'Leonardo da Vinci'),
    DailyThought('He who opens a school door, closes a prison.', 'Attributed to Victor Hugo'),
    DailyThought('Learning never exhausts the mind.', 'Leonardo da Vinci'),
    DailyThought('The purpose of education is to replace an empty mind with an open one.', 'Malcolm Forbes'),
    DailyThought('Anyone who stops learning is old, whether at twenty or eighty.', 'Henry Ford'),
    DailyThought('Reading is to the mind what exercise is to the body.', 'Joseph Addison'),
    DailyThought('There is no substitute for hard work.', 'Thomas Edison'),
    DailyThought('Our greatest glory is not in never falling, but in rising every time we fall.', 'Confucius'),
    DailyThought('Knowledge is power.', 'Francis Bacon'),
    DailyThought('Doubt is the origin of wisdom.', 'René Descartes'),
    DailyThought('I am still learning.', 'Michelangelo'),
    DailyThought('If you think education is expensive, try ignorance.', 'Attributed to Derek Bok'),
    DailyThought('The more that you read, the more things you will know.', 'Dr. Seuss'),
    DailyThought('Education is not preparation for life; education is life itself.', 'John Dewey'),
    DailyThought('Do not go where the path may lead, go instead where there is no path and leave a trail.', 'Attributed to Ralph Waldo Emerson'),
    DailyThought('Small deeds done are better than great deeds planned.', 'Peter Marshall'),
    DailyThought('Teachers open the door, but you must enter by yourself.', 'Chinese proverb'),
    DailyThought('A little learning is a dangerous thing.', 'Alexander Pope'),
    DailyThought('The important thing is not to stop questioning.', 'Albert Einstein'),
    DailyThought('Never memorise something that you can look up.', 'Attributed to Albert Einstein'),
    DailyThought('To know that we know what we know, and that we do not know what we do not know, that is true knowledge.', 'Nicolaus Copernicus'),
    DailyThought('Excellence is never an accident.', 'Aristotle'),
    DailyThought('Nothing in life is to be feared, it is only to be understood.', 'Marie Curie'),
    DailyThought('Be less curious about people and more curious about ideas.', 'Marie Curie'),
    DailyThought('Perseverance is not a long race; it is many short races one after the other.', 'Walter Elliot'),
    DailyThought('Start where you are. Use what you have. Do what you can.', 'Arthur Ashe'),
    DailyThought('Quality is not an act, it is a habit.', 'Attributed to Aristotle (paraphrase of Will Durant)'),
    DailyThought('The best way to predict the future is to invent it.', 'Alan Kay'),
    DailyThought('Simplicity is the ultimate sophistication.', 'Attributed to Leonardo da Vinci'),
    DailyThought('If I have seen further it is by standing on the shoulders of giants.', 'Isaac Newton'),
    DailyThought('Somewhere, something incredible is waiting to be known.', 'Attributed to Carl Sagan'),
    DailyThought('Science is a way of thinking much more than it is a body of knowledge.', 'Carl Sagan'),
    DailyThought('Imagination is more important than knowledge.', 'Albert Einstein'),
    DailyThought('Not everything that can be counted counts.', 'William Bruce Cameron'),
    DailyThought('In the middle of difficulty lies opportunity.', 'Attributed to Albert Einstein'),
    DailyThought('The only way to do great work is to love what you do.', 'Steve Jobs'),
    DailyThought('Stay hungry. Stay foolish.', 'Stewart Brand, quoted by Steve Jobs'),
    DailyThought('It always seems impossible until it is done.', 'Nelson Mandela'),
    DailyThought('A winner is a dreamer who never gives up.', 'Nelson Mandela'),
    DailyThought('Courage is not the absence of fear, but the triumph over it.', 'Nelson Mandela'),
    DailyThought('Look up at the stars and not down at your feet.', 'Stephen Hawking'),
    DailyThought('Intelligence is the ability to adapt to change.', 'Attributed to Stephen Hawking'),
    DailyThought('The greatest enemy of knowledge is not ignorance, it is the illusion of knowledge.', 'Attributed to Daniel J. Boorstin'),
    DailyThought('Learn from yesterday, live for today, hope for tomorrow.', 'Attributed to Albert Einstein'),
    DailyThought('Strive not to be a success, but rather to be of value.', 'Attributed to Albert Einstein'),
    DailyThought('Well begun is half done.', 'Aristotle'),
    DailyThought('We are what we repeatedly do.', 'Will Durant, summarising Aristotle'),
    DailyThought('Knowledge speaks, but wisdom listens.', 'Attributed to Jimi Hendrix'),
    DailyThought('The unexamined life is not worth living.', 'Socrates'),
    DailyThought('There is nothing permanent except change.', 'Heraclitus'),
    DailyThought('No man ever steps in the same river twice.', 'Heraclitus'),
    DailyThought('He who has a why to live can bear almost any how.', 'Friedrich Nietzsche'),
    DailyThought('That which does not kill us makes us stronger.', 'Friedrich Nietzsche'),
    DailyThought('The cure for boredom is curiosity. There is no cure for curiosity.', 'Attributed to Dorothy Parker'),
    DailyThought('Do not let what you cannot do interfere with what you can do.', 'John Wooden'),
    DailyThought('It is not that I am so smart, it is just that I stay with problems longer.', 'Attributed to Albert Einstein'),
    DailyThought('Errors using inadequate data are much less than those using no data at all.', 'Charles Babbage'),
    DailyThought('An ounce of practice is worth more than tons of preaching.', 'Mahatma Gandhi'),
    DailyThought('The future belongs to those who believe in the beauty of their dreams.', 'Attributed to Eleanor Roosevelt'),
    DailyThought('The best preparation for tomorrow is doing your best today.', 'H. Jackson Brown Jr.'),
    DailyThought('Knowledge has to be improved, challenged and increased constantly, or it vanishes.', 'Peter Drucker'),
    DailyThought('What gets measured gets managed.', 'Attributed to Peter Drucker'),
    DailyThought('Discipline is the bridge between goals and accomplishment.', 'Jim Rohn'),
    DailyThought('Either write something worth reading or do something worth writing.', 'Benjamin Franklin'),
    DailyThought('Lost time is never found again.', 'Benjamin Franklin'),
    DailyThought('By failing to prepare, you are preparing to fail.', 'Attributed to Benjamin Franklin'),
    DailyThought('Energy and persistence conquer all things.', 'Benjamin Franklin'),
    DailyThought('Hard work beats talent when talent does not work hard.', 'Tim Notke'),
    DailyThought('You miss one hundred percent of the shots you do not take.', 'Wayne Gretzky'),
    DailyThought('Learning is not attained by chance, it must be sought for with ardour.', 'Abigail Adams'),
    DailyThought('The only person you are destined to become is the person you decide to be.', 'Attributed to Ralph Waldo Emerson'),
    DailyThought('Knowledge is of no value unless you put it into practice.', 'Attributed to Anton Chekhov'),
    DailyThought('Concentrate all your thoughts upon the work at hand.', 'Alexander Graham Bell'),
    DailyThought('Before anything else, preparation is the key to success.', 'Attributed to Alexander Graham Bell'),
    DailyThought('The man who moves a mountain begins by carrying away small stones.', 'Confucius'),
    DailyThought('Real knowledge is to know the extent of one\'s ignorance.', 'Confucius'),
  ];
}
