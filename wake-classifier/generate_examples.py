#!/usr/bin/env python3

import os
import random

# Templates for positive examples (addressing Goose directly)
positive_templates = [
    "Hey Goose, {question}",
    "Goose, {question}",
    "I was wondering, Goose, {question}",
    "Could you {request}, Goose?",
    "{question}, Goose?",
    "Goose, I need help with {topic}.",
    "I need your assistance, Goose. {request}",
    "Goose, would you be able to {request}?",
    "Do you think, Goose, that {question}",
    "I'm curious, Goose, {question}",
    "Goose, I'd like to know {topic}.",
    "Can you tell me, Goose, {question}",
    "Hey Goose! {request}",
    "Goose, I've been thinking about {topic} and {question}",
    "I'd appreciate it if you could {request}, Goose.",
    "Goose, what's your opinion on {topic}?",
    "I need some advice, Goose, about {topic}.",
    "Goose, could you explain {topic} to me?",
    "I'm stuck on this problem, Goose. {question}",
    "Goose, I'm trying to {request}, can you help?",
]

# Questions, requests and topics for positive examples
questions = [
    "what's the weather like today?",
    "how do I solve this equation?",
    "what's the best way to learn Python?",
    "can you recommend a good book?",
    "what's the capital of France?",
    "how do neural networks work?",
    "what are the symptoms of the flu?",
    "how do I make pasta from scratch?",
    "what's the meaning of this phrase?",
    "how do I fix this error in my code?",
    "what's the history of the internet?",
    "how do I improve my public speaking?",
    "what's the difference between RAM and ROM?",
    "how do I create a budget?",
    "what's the best way to learn a new language?",
    "how do I start investing?",
    "what are the benefits of meditation?",
    "how do I write a resume?",
    "what's the meaning of life?",
    "how do I train my dog?",
    "what's the tallest mountain in the world?",
    "how do I improve my sleep?",
    "what are some healthy breakfast ideas?",
    "how do I set up a home network?",
    "what's the best exercise for weight loss?",
    "how do I grow tomatoes?",
    "what's the plot of that famous book?",
    "how do I change a tire?",
    "what are the planets in our solar system?",
    "how do I negotiate a salary?",
]

requests = [
    "help me with this math problem",
    "explain quantum physics",
    "translate this sentence to Spanish",
    "write a poem about nature",
    "summarize this article",
    "draft an email to my boss",
    "create a workout plan",
    "suggest a recipe for dinner",
    "help me debug this code",
    "plan my trip to Japan",
    "recommend a movie to watch",
    "write a cover letter",
    "create a study schedule",
    "explain how blockchain works",
    "suggest some team building activities",
    "help me organize my closet",
    "create a marketing strategy",
    "explain the rules of chess",
    "help me with my homework",
    "suggest a gift for my mom",
    "create a bedtime story",
    "explain how to use this software",
    "help me practice for an interview",
    "create a to-do list for today",
    "suggest ways to reduce stress",
    "help me learn guitar chords",
    "create a budget plan",
    "explain how to fix my printer",
    "suggest books on leadership",
    "help me improve my writing",
]

topics = [
    "artificial intelligence",
    "climate change",
    "quantum computing",
    "cryptocurrency",
    "machine learning",
    "renewable energy",
    "space exploration",
    "virtual reality",
    "genetic engineering",
    "blockchain technology",
    "cybersecurity",
    "digital marketing",
    "remote work",
    "sustainable living",
    "mental health",
    "personal finance",
    "nutrition and diet",
    "exercise science",
    "career development",
    "language learning",
    "parenting techniques",
    "home improvement",
    "gardening",
    "cooking techniques",
    "photography",
    "music theory",
    "art history",
    "creative writing",
    "public speaking",
    "time management",
]

# Templates for negative examples (not addressing Goose directly)
negative_templates = [
    # General conversation
    "I need to remember to {general_task}.",
    "Did you know that {fact}?",
    "I'm thinking about {general_topic} lately.",
    "Have you ever tried {activity}?",
    "I wonder if {question_indirect}.",
    "The other day I was {activity} and {observation}.",
    "My friend told me that {statement}.",
    "I read an article about {general_topic} yesterday.",
    "I'm planning to {general_task} this weekend.",
    "What do you think about {general_topic}?",
    
    # Mentioning goose as an animal or in idioms
    "I saw a goose at the park yesterday and {goose_observation}.",
    "The idiom 'a wild goose chase' means {idiom_explanation}.",
    "Did you know that Canada geese {goose_fact}?",
    "My grandmother used to cook goose for {occasion}.",
    "The children's game duck, duck, goose is {game_description}.",
    
    # Mentioning Goose but not addressing it
    "I heard about this AI called Goose that {goose_ai_description}.",
    "My friend uses Goose to {goose_ai_usage}.",
    "There's an app called Goose that {app_description}.",
    "The character Goose in that movie was {character_description}.",
    "That restaurant 'The Golden Goose' serves {food_description}.",
    
    # Talking about Goose in third person
    "I asked Goose yesterday about {topic} and it {goose_response}.",
    "Goose told me that {goose_statement} when I asked earlier.",
    "I think Goose is really good at {goose_capability}.",
    "Sometimes Goose gives {response_description} answers.",
    "I wonder if Goose knows about {topic}.",
    
    # Addressing other assistants
    "Hey Siri, {siri_request}",
    "Alexa, {alexa_request}",
    "OK Google, {google_request}",
    "Cortana, could you {cortana_request}?",
    "Hey Jarvis, {jarvis_request}",
]

# Content for negative examples
general_tasks = [
    "pick up groceries",
    "call my mom",
    "finish that report",
    "book a dentist appointment",
    "renew my passport",
    "fix the leaky faucet",
    "pay the electricity bill",
    "send that email to HR",
    "return those library books",
    "clean out the garage",
    "schedule a haircut",
    "update my resume",
    "buy a birthday gift",
    "back up my photos",
    "register for that class",
]

facts = [
    "honey never spoils",
    "octopuses have three hearts",
    "a group of flamingos is called a flamboyance",
    "cows have best friends",
    "the Great Wall of China is not visible from space",
    "bananas are berries but strawberries aren't",
    "a day on Venus is longer than a year on Venus",
    "the shortest war in history lasted 38 minutes",
    "the world's oldest known living tree is over 5,000 years old",
    "the fingerprints of koalas are similar to humans",
    "the Hawaiian alphabet only has 12 letters",
    "a bolt of lightning is five times hotter than the surface of the sun",
    "cats can't taste sweetness",
    "the Eiffel Tower can be 15 cm taller during summer",
    "the human nose can detect over 1 trillion scents",
]

general_topics = [
    "renewable energy",
    "that new sci-fi show",
    "learning to play guitar",
    "the housing market",
    "plant-based diets",
    "cryptocurrency trends",
    "mindfulness meditation",
    "travel destinations",
    "home automation",
    "remote work culture",
    "sustainable fashion",
    "digital privacy",
    "urban gardening",
    "the latest smartphone",
    "local politics",
]

activities = [
    "rock climbing",
    "making sourdough bread",
    "learning to code",
    "taking a pottery class",
    "volunteering at an animal shelter",
    "trying that new restaurant",
    "meditating every morning",
    "keeping a gratitude journal",
    "playing in a community orchestra",
    "joining a book club",
    "taking dance lessons",
    "growing my own vegetables",
    "restoring vintage furniture",
    "learning a new language",
    "starting a podcast",
]

questions_indirect = [
    "it's going to rain tomorrow",
    "this recipe would work with almond flour instead",
    "they're going to announce a new product soon",
    "the movie is worth watching",
    "the train will be delayed again",
    "that restaurant is still open",
    "she got the job she applied for",
    "the package will arrive on time",
    "the concert tickets will sell out quickly",
    "the company will approve my vacation request",
    "the book will have a sequel",
    "the store has my size in stock",
    "the meeting will be rescheduled",
    "the flight will be delayed",
    "the game will go into overtime",
]

observations = [
    "it was surprisingly fun",
    "I learned something new",
    "it made me think differently",
    "I realized I need more practice",
    "it was harder than I expected",
    "I met some interesting people",
    "it changed my perspective",
    "I discovered a hidden talent",
    "it was quite challenging",
    "I enjoyed it more than I thought I would",
    "it was a complete disaster",
    "I couldn't stop laughing",
    "it was a waste of time",
    "I had an epiphany",
    "it was exactly what I needed",
]

statements = [
    "they're moving to another country next month",
    "the restaurant we like is closing down",
    "they got a promotion at work",
    "their dog learned an amazing trick",
    "the movie ending was completely different in the book",
    "the concert was canceled last minute",
    "they found a rare coin in their backyard",
    "the traffic was terrible this morning",
    "the local café changed their menu",
    "they're learning to play the piano",
    "the weather forecast is wrong again",
    "they met a celebrity at the airport",
    "the neighbor's cat keeps visiting their house",
    "they're planning a surprise party",
    "the new store has amazing discounts",
]

goose_observations = [
    "it was chasing all the visitors",
    "it had the most beautiful feathers",
    "it was swimming with its goslings",
    "it was surprisingly friendly",
    "it was making the loudest honking noise",
    "it was eating right out of people's hands",
    "it seemed to be guarding the area",
    "it was bigger than any goose I've seen before",
    "it kept following me around",
    "it was building a nest",
    "it was fighting with another goose",
    "it looked like it was posing for photos",
    "it had a distinctive marking on its head",
    "it was teaching its babies to swim",
    "it seemed to be injured",
]

idiom_explanations = [
    "pursuing something that's pointless or impossible to achieve",
    "wasting time on a futile search",
    "chasing after something that doesn't exist",
    "going on a hopeless quest",
    "following a false lead",
    "embarking on a foolish pursuit",
    "searching for something unattainable",
    "looking for something that can't be found",
    "pursuing a fruitless endeavor",
    "following a deceptive trail",
]

goose_facts = [
    "mate for life",
    "can fly at altitudes of 29,000 feet",
    "have excellent memories and can recognize human faces",
    "can live up to 25 years in the wild",
    "fly in a V formation to conserve energy",
    "have teeth on their tongues",
    "can sleep with one eye open",
    "can travel more than 1,000 miles in a day",
    "return to the same nesting grounds year after year",
    "have over 10,000 feathers",
]

occasions = [
    "Christmas dinner",
    "Thanksgiving",
    "special family gatherings",
    "harvest festivals",
    "New Year's celebrations",
    "winter solstice",
    "anniversary dinners",
    "Sunday roasts",
    "traditional holidays",
    "autumn feasts",
]

game_descriptions = [
    "a classic children's game that teaches quick reactions",
    "still popular at birthday parties",
    "one of my favorite childhood memories",
    "a great way to get kids moving and laughing",
    "surprisingly competitive even among adults",
    "a simple game that never seems to go out of style",
    "fun until someone gets too excited and falls down",
    "a game I haven't played since elementary school",
    "always ends with everyone out of breath",
    "a game that always leads to chaos and laughter",
]

goose_ai_descriptions = [
    "can help with coding problems",
    "answers questions about almost anything",
    "helps people write essays and emails",
    "is being developed by a major tech company",
    "specializes in creative writing",
    "can generate images from text descriptions",
    "is designed specifically for educational purposes",
    "helps with data analysis and visualization",
    "can translate between dozens of languages",
    "is particularly good at explaining complex topics",
]

goose_ai_usages = [
    "help with homework assignments",
    "draft business emails",
    "generate creative content",
    "learn new programming languages",
    "research topics quickly",
    "plan travel itineraries",
    "create study guides",
    "brainstorm business ideas",
    "edit and proofread documents",
    "translate documents into different languages",
]

app_descriptions = [
    "helps you track your daily habits",
    "reminds you to stay hydrated",
    "organizes your tasks by priority",
    "connects freelancers with potential clients",
    "generates workout routines based on your goals",
    "helps you learn languages through immersion",
    "tracks your sleep patterns",
    "helps you meditate with guided sessions",
    "manages your subscription services",
    "creates meal plans based on what's in your fridge",
]

character_descriptions = [
    "the loyal sidekick",
    "known for that famous scene",
    "a fan favorite character",
    "tragically killed off too soon",
    "played by that famous actor",
    "based on a real historical figure",
    "the comic relief of the story",
    "more complex than people give credit for",
    "inspired a lot of merchandise",
    "the breakout character of the series",
]

food_descriptions = [
    "the most amazing brunch in town",
    "traditional recipes with a modern twist",
    "farm-to-table dishes at reasonable prices",
    "incredible desserts that look like works of art",
    "comfort food that reminds you of home",
    "seasonal ingredients from local farmers",
    "fusion cuisine that actually works",
    "small plates perfect for sharing",
    "a tasting menu that changes monthly",
    "authentic dishes from a specific region",
]

goose_responses = [
    "gave me a detailed explanation",
    "suggested some interesting alternatives",
    "provided step-by-step instructions",
    "shared some fascinating facts",
    "couldn't really help with that specific question",
    "surprised me with its creative answer",
    "recommended some useful resources",
    "explained it in a way that finally made sense",
    "generated a comprehensive list of options",
    "offered a perspective I hadn't considered",
]

goose_statements = [
    "the best approach would be to start small",
    "it's actually a common misconception",
    "there are several ways to solve this problem",
    "the research on this topic is still evolving",
    "it's important to consider multiple perspectives",
    "the historical context is crucial to understanding",
    "practice is more important than natural talent",
    "the trend is likely to continue in coming years",
    "the underlying principles are actually quite simple",
    "many experts disagree on this particular point",
]

goose_capabilities = [
    "explaining complex topics simply",
    "finding creative solutions to problems",
    "summarizing long articles",
    "translating between languages",
    "generating code examples",
    "providing balanced perspectives",
    "creating educational content",
    "helping with writing tasks",
    "answering obscure questions",
    "organizing information clearly",
]

response_descriptions = [
    "surprisingly detailed",
    "thoughtful and nuanced",
    "concise but comprehensive",
    "creative and unexpected",
    "technically accurate",
    "easy to understand",
    "well-researched",
    "practical and actionable",
    "personalized to my needs",
    "balanced and unbiased",
]

siri_requests = [
    "set a timer for 20 minutes",
    "what's the weather forecast for tomorrow?",
    "call Mom on speaker",
    "how tall is the Empire State Building?",
    "play my favorite playlist",
    "what's on my calendar today?",
    "send a text to John",
    "what's the traffic like on my commute?",
    "remind me to pick up milk later",
    "what movies are playing nearby?",
]

alexa_requests = [
    "play some jazz music",
    "add paper towels to my shopping list",
    "what time is it in Tokyo?",
    "set an alarm for 7 AM",
    "tell me a joke",
    "what's the score of the game?",
    "turn on the living room lights",
    "what's the definition of serendipity?",
    "how many ounces are in a cup?",
    "read my Audible book",
]

google_requests = [
    "how do I get to the nearest gas station?",
    "what's the capital of Peru?",
    "set a reminder for my doctor's appointment",
    "what's the conversion rate between dollars and euros?",
    "play music on Spotify",
    "what's the recipe for banana bread?",
    "how old is Tom Hanks?",
    "turn off the kitchen light",
    "what's in the news today?",
    "translate 'hello' to Japanese",
]

cortana_requests = [
    "open Microsoft Word",
    "what meetings do I have today?",
    "send an email to the team",
    "what's the status of my flight?",
    "show me my to-do list",
    "find files I worked on yesterday",
    "create a new calendar event",
    "what's the weather like?",
    "remind me about the project deadline",
    "search the web for recent tech news",
]

jarvis_requests = [
    "run a diagnostic on the system",
    "what's the status of the Mark VII suit?",
    "order more coffee for the lab",
    "pull up the schematics for the new project",
    "what's my schedule for today?",
    "analyze this data set",
    "connect me with Pepper",
    "deploy the security protocols",
    "what's the weather forecast?",
    "play my workshop playlist",
]

def generate_positive_example():
    template = random.choice(positive_templates)
    if "{topic}" in template and "{question}" in template:
        return template.format(topic=random.choice(topics), question=random.choice(questions))
    elif "{question}" in template:
        return template.format(question=random.choice(questions))
    elif "{request}" in template:
        return template.format(request=random.choice(requests))
    elif "{topic}" in template:
        return template.format(topic=random.choice(topics))
    return "Hey Goose, " + random.choice(questions)

def generate_negative_example():
    template = random.choice(negative_templates)
    
    # General conversation templates
    if "{general_task}" in template:
        return template.format(general_task=random.choice(general_tasks))
    elif "{fact}" in template:
        return template.format(fact=random.choice(facts))
    elif "{general_topic}" in template:
        return template.format(general_topic=random.choice(general_topics))
    elif "{activity}" in template and "{observation}" in template:
        return template.format(activity=random.choice(activities), observation=random.choice(observations))
    elif "{activity}" in template:
        return template.format(activity=random.choice(activities))
    elif "{question_indirect}" in template:
        return template.format(question_indirect=random.choice(questions_indirect))
    elif "{statement}" in template:
        return template.format(statement=random.choice(statements))
    
    # Goose animal/idiom templates
    elif "{goose_observation}" in template:
        return template.format(goose_observation=random.choice(goose_observations))
    elif "{idiom_explanation}" in template:
        return template.format(idiom_explanation=random.choice(idiom_explanations))
    elif "{goose_fact}" in template:
        return template.format(goose_fact=random.choice(goose_facts))
    elif "{occasion}" in template:
        return template.format(occasion=random.choice(occasions))
    elif "{game_description}" in template:
        return template.format(game_description=random.choice(game_descriptions))
    
    # Goose AI templates (not addressing directly)
    elif "{goose_ai_description}" in template:
        return template.format(goose_ai_description=random.choice(goose_ai_descriptions))
    elif "{goose_ai_usage}" in template:
        return template.format(goose_ai_usage=random.choice(goose_ai_usages))
    elif "{app_description}" in template:
        return template.format(app_description=random.choice(app_descriptions))
    elif "{character_description}" in template:
        return template.format(character_description=random.choice(character_descriptions))
    elif "{food_description}" in template:
        return template.format(food_description=random.choice(food_descriptions))
    
    # Talking about Goose in third person
    elif "{goose_response}" in template:
        return template.format(topic=random.choice(topics), goose_response=random.choice(goose_responses))
    elif "{goose_statement}" in template:
        return template.format(goose_statement=random.choice(goose_statements))
    elif "{goose_capability}" in template:
        return template.format(goose_capability=random.choice(goose_capabilities))
    elif "{response_description}" in template:
        return template.format(response_description=random.choice(response_descriptions))
    elif "{topic}" in template:
        return template.format(topic=random.choice(topics))
    
    # Other assistants
    elif "{siri_request}" in template:
        return template.format(siri_request=random.choice(siri_requests))
    elif "{alexa_request}" in template:
        return template.format(alexa_request=random.choice(alexa_requests))
    elif "{google_request}" in template:
        return template.format(google_request=random.choice(google_requests))
    elif "{cortana_request}" in template:
        return template.format(cortana_request=random.choice(cortana_requests))
    elif "{jarvis_request}" in template:
        return template.format(jarvis_request=random.choice(jarvis_requests))
    
    return "I was thinking about " + random.choice(general_topics) + " today."

# Create directories if they don't exist
os.makedirs("data/positive/batch3", exist_ok=True)
os.makedirs("data/negative/batch3", exist_ok=True)

# Generate positive examples
for i in range(1, 201):
    example = generate_positive_example()
    with open(f"data/positive/batch3/example{i}.txt", "w") as f:
        f.write(example)

# Generate negative examples
for i in range(1, 201):
    example = generate_negative_example()
    with open(f"data/negative/batch3/example{i}.txt", "w") as f:
        f.write(example)

print("Generated 200 positive and 200 negative examples in batch3 folders.")