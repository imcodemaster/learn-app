"""
Sample content for `python manage.py seed_demo`.

Course names, study-center fees and contact details come from
learnincreation.com. Online-course prices are SAMPLE values — change them in
the admin. Lesson texts are short starter lessons you can edit or replace.
"""

ABOUT = (
    "LearnInCreation makes computer education practical, affordable and accessible. "
    "Students, beginners, job seekers and working professionals build in-demand digital skills "
    "through easy-to-follow lessons and hands-on practice — online, or in person at our study "
    "center in Rudrapur, Uttarakhand.\n\n"
    "We are incubated by FIED (Foundation for Innovation and Entrepreneurship Development) at IIM Kashipur."
)

FAQS = [
    ("What is LearnInCreation?",
     "A computer education platform from Rudrapur that teaches beginner-friendly computer basics, "
     "office software, web development, programming and digital marketing."),
    ("Who can join the courses?",
     "Students, beginners, job seekers and anyone who wants computer or digital skills. "
     "Most basic courses need no prior experience."),
    ("Are the courses suitable for beginners?",
     "Yes. Lessons start from the basics with clear explanations, guided steps and hands-on practice."),
    ("Will I receive a certificate?",
     "It depends on the course. Check the course details or contact us to ask about certification."),
    ("How does seat booking at the study center work?",
     "Open the Study Center tab, pick a course batch or a library shift, choose a free seat on the map and "
     "pay online. Your seat is held for a few minutes while you pay."),
    ("Is paying in the app safe?",
     "Payments are handled by Razorpay. Your card, UPI and bank details go straight to Razorpay and are never "
     "stored by LearnInCreation."),
    ("Can I cancel a booking?",
     "Bookings that are still awaiting payment can be cancelled in the app. For paid bookings, please contact "
     "the study center."),
]

CATEGORIES = [
    # slug, name, icon, description
    ("computer-basics", "Computer Basics", "computer", "Start here: how computers work and everyday computer skills."),
    ("microsoft-office", "Microsoft Office", "description", "Word, Excel and PowerPoint for school, office and business."),
    ("web-design", "Web Design & Development", "web", "Build websites with HTML5, CSS3, Bootstrap and more."),
    ("programming", "Programming", "code", "Learn to code with Python and JavaScript."),
    ("digital-marketing", "Digital Marketing", "campaign", "Grow a business online with SEO and social media."),
    ("it-networking", "IT & Networking", "dns", "Operating systems, networks and Linux."),
]

# slug, title, category, subtitle, price, mrp, duration, featured, outcomes
COURSES = [
    ("basics-of-computer-fundamentals", "Basics of Computer Fundamentals", "computer-basics",
     "Hardware, software, memory and everyday computer skills — from zero.", 0, 0, "2–3 months", True,
     ["Explain what a computer is and how it works", "Name the main hardware parts and what they do",
      "Tell system software from application software", "Understand memory, storage and file sizes"]),
    ("operating-systems-fundamentals", "Operating Systems Fundamentals", "it-networking",
     "What an operating system does, with Windows and Linux examples.", 0, 0, "1 month", False,
     ["Understand processes, files and users", "Manage files and folders confidently"]),
    ("networking-fundamentals", "Networking Fundamentals", "it-networking",
     "How computers talk: IP addresses, routers, Wi-Fi and the internet.", 499, 999, "2–3 months", False,
     ["Explain LAN, WAN and the internet", "Understand IP addresses and DNS"]),
    ("linux-commands-for-beginners", "Linux Commands for Beginners", "it-networking",
     "Use the Linux terminal with confidence.", 0, 0, "1 month", False,
     ["Move around the file system", "Create, copy, move and delete files from the terminal"]),
    ("microsoft-word-for-beginners", "Microsoft Word for Beginners", "microsoft-office",
     "Create, format and print professional documents.", 0, 0, "1 month", False,
     ["Format text and paragraphs", "Insert tables, images and page numbers"]),
    ("microsoft-word-advanced", "Microsoft Word Advanced", "microsoft-office",
     "Styles, mail merge, templates and long documents.", 299, 599, "1–2 months", False,
     ["Use styles and automatic tables of contents", "Run a mail merge"]),
    ("microsoft-excel-for-beginners", "Microsoft Excel for Beginners", "microsoft-office",
     "Spreadsheets, formulas and charts for everyday work.", 299, 599, "1–2 months", True,
     ["Enter and format data", "Use SUM, AVERAGE, IF and other common formulas", "Create charts"]),
    ("powerpoint-for-beginners", "PowerPoint for Beginners", "microsoft-office",
     "Make clear, good-looking presentations.", 0, 0, "1 month", False,
     ["Design slides with themes and layouts", "Add images, shapes and transitions"]),
    ("powerpoint-advanced", "PowerPoint Advanced", "microsoft-office",
     "Animations, slide masters and presenting like a pro.", 299, 599, "1 month", False,
     ["Use slide masters", "Build smooth animations"]),
    ("proficiency-in-microsoft-office", "Proficiency in Microsoft Office", "microsoft-office",
     "Word, Excel and PowerPoint together in one complete course.", 799, 1499, "2–3 months", False,
     ["Work confidently in Word, Excel and PowerPoint"]),
    ("introduction-to-html5", "Introduction to HTML5", "web-design",
     "Build your first web pages with HTML5.", 299, 599, "1–2 months", True,
     ["Understand tags, elements and attributes", "Build a complete web page from scratch"]),
    ("design-with-css3", "Design with CSS3", "web-design",
     "Style web pages: colours, layouts, Flexbox and responsive design.", 399, 799, "1–2 months", False,
     ["Style text, colours and spacing", "Build layouts with Flexbox"]),
    ("introduction-to-bootstrap", "Introduction to Bootstrap", "web-design",
     "Build responsive websites quickly with Bootstrap.", 399, 799, "1 month", False,
     ["Use the Bootstrap grid", "Use ready-made components"]),
    ("introduction-to-web-designing", "Introduction to Web Designing", "web-design",
     "HTML, CSS and Bootstrap together: design and publish a website.", 999, 1999, "2–3 months", True,
     ["Plan and design a website", "Publish a site online"]),
    ("introduction-to-javascript", "Introduction to JavaScript", "programming",
     "Make web pages interactive with JavaScript.", 499, 999, "2 months", False,
     ["Write variables, functions and loops", "Respond to clicks and form input"]),
    ("python-for-beginners", "Python for Beginners", "programming",
     "Your first programming language — simple, powerful Python.", 499, 999, "2–3 months", True,
     ["Install Python and run programs", "Use variables, data types and input/output",
      "Write decisions and loops", "Solve small real-world problems in code"]),
    ("web-development-with-python", "Web Development with Python", "programming",
     "Build web applications with Python.", 999, 1999, "2–3 months", False,
     ["Understand how web apps work", "Build a small web app"]),
    ("introduction-to-digital-marketing", "Introduction to Digital Marketing", "digital-marketing",
     "SEO, social media, ads and email — how businesses grow online.", 799, 1499, "2–3 months", True,
     ["Plan a digital marketing strategy", "Understand SEO, social media and paid ads"]),
    ("facebook-marketing", "Facebook Marketing", "digital-marketing",
     "Pages, posts, groups and ads that reach the right people.", 599, 1199, "1–2 months", False,
     ["Set up and grow a Facebook page", "Run a simple ad campaign"]),
    ("search-engine-optimization", "Search Engine Optimization (SEO)", "digital-marketing",
     "Help your website rank on Google.", 599, 1199, "1–2 months", False,
     ["Research keywords", "Optimise pages and build links"]),
]

COMPUTER_LESSONS = [
    ("Getting started", "What Is a Computer?", True, """
A **computer** is an electronic machine that takes in data, processes it using instructions, stores the results and gives us useful output.

## The IPO cycle

Every computer task follows the same simple cycle:

1. **Input** – data goes in (you type, click, speak or scan).
2. **Process** – the processor works on the data using a program.
3. **Output** – you see or hear the result (screen, printer, speakers).
4. **Storage** – results can be saved to use later.

> **Example:** You type `25 + 17` into a calculator app (input), the processor adds the numbers (process), and `42` appears on the screen (output).

## Why computers are so useful

| Feature | What it means |
| --- | --- |
| Speed | Millions of calculations every second |
| Accuracy | Same correct answer every time when the instructions are right |
| Storage | Keeps huge amounts of data for years |
| Versatility | One machine can write letters, play music and run a shop |

## Key point

A computer does nothing on its own — it follows **instructions** written by people. Those instructions are called **programs** or **software**.
"""),
    ("Getting started", "A Short History of Computers", False, """
Computers did not appear overnight. They grew out of centuries of counting tools.

## Early calculating devices

- **Abacus** (thousands of years ago) – beads on rods used for counting.
- **Pascaline** (1642) – Blaise Pascal's mechanical adding machine.
- **Analytical Engine** (1830s) – Charles Babbage's design for a programmable machine. Babbage is often called the *father of the computer*.

## The five generations

| Generation | Years (approx.) | Main technology |
| --- | --- | --- |
| First | 1940–1956 | Vacuum tubes |
| Second | 1956–1963 | Transistors |
| Third | 1964–1971 | Integrated circuits (ICs) |
| Fourth | 1971–today | Microprocessors |
| Fifth | Today and beyond | Artificial intelligence |

Each generation made computers **smaller, faster, cheaper and more reliable**. The phone in your pocket is far more powerful than room-sized computers from the 1950s.

> **Remember:** The microprocessor (a whole processor on one chip) is what made personal computers possible.
"""),
    ("Getting started", "Types of Computers", False, """
Computers come in many sizes, built for different jobs.

## By size and power

- **Supercomputers** – the fastest machines, used for weather forecasting and space research.
- **Mainframes** – large systems that handle millions of transactions, e.g. banks and railway booking.
- **Minicomputers / servers** – serve many users at once in offices and websites.
- **Microcomputers** – personal computers: desktops, laptops, tablets and smartphones.

## By how they work

- **Analog** – measure continuous values (old speedometers, thermometers).
- **Digital** – work with numbers (0 and 1); almost all modern computers.
- **Hybrid** – combine both, e.g. machines in hospital ICUs.

## Quick check

Which type of computer is used for booking train tickets across India?

> **Answer:** A mainframe or a cluster of large servers — it must handle a huge number of users at the same time.
"""),
    ("Inside the computer", "Hardware and Software", False, """
A computer has two parts that always work together.

## Hardware

**Hardware** is every physical part you can touch:

- **CPU (Central Processing Unit)** – the "brain" that runs instructions.
- **Motherboard** – the main board that connects all parts.
- **RAM** – short-term working memory.
- **Storage** – hard disk (HDD) or solid-state drive (SSD).
- **Power supply, cabinet, keyboard, mouse, monitor** and more.

## Software

**Software** is the set of programs that tell the hardware what to do. There are two main kinds:

| System software | Application software |
| --- | --- |
| Runs the computer itself | Helps you do a task |
| Windows, Linux, Android, device drivers | MS Word, Chrome, Tally, games |

> **Tip:** Hardware without software is like a car without a driver. Software without hardware is like a driver without a car.
"""),
    ("Inside the computer", "Input and Output Devices", False, """
## Input devices — data goes **in**

- Keyboard, mouse, touchpad, touch screen
- Scanner and webcam
- Microphone
- Barcode reader and biometric (fingerprint) scanner

## Output devices — results come **out**

- Monitor (screen)
- Printer
- Speakers and headphones
- Projector

## Devices that do both

Some devices are **input and output** at the same time:

- **Touch screen** – shows output and takes your touch as input.
- **Headset with a microphone**.
- **Network card / modem** – sends and receives data.

> **Practice:** Look around your room and list three input devices and three output devices.
"""),
    ("Inside the computer", "Memory and Storage", False, """
## Measuring data

Computers store everything as **bits** (0 or 1).

| Unit | Size |
| --- | --- |
| 1 Byte | 8 bits |
| 1 Kilobyte (KB) | 1024 bytes |
| 1 Megabyte (MB) | 1024 KB |
| 1 Gigabyte (GB) | 1024 MB |
| 1 Terabyte (TB) | 1024 GB |

## Primary memory

- **RAM** – fast working memory. It is *volatile*: everything in it is lost when power goes off.
- **ROM** – stores start-up instructions permanently. It is *non-volatile*.
- **Cache** – very small, very fast memory inside or near the CPU.

## Secondary storage

Keeps your files even when the computer is switched off:

- **HDD** – large and cheap, but slower.
- **SSD** – much faster, no moving parts.
- **Pen drives, memory cards, DVDs** and **cloud storage**.

> **Remember:** More RAM helps you run more programs at once. More storage lets you keep more files.
"""),
]

PYTHON_LESSONS = [
    ("Getting started", "Why Learn Python?", True, """
**Python** is one of the world's most popular programming languages — and one of the easiest to start with.

## What Python is used for

- Websites and web apps
- Data analysis and AI
- Automating boring office tasks
- Games, scripts and school projects

## Why beginners love it

Python reads almost like English. Compare printing a message:

```python
print("Hello, LearnInCreation!")
```

That single line is a complete program.

> **Goal of this course:** by the end you will write small programs that solve real problems — like a marks calculator or a simple billing program.
"""),
    ("Getting started", "Installing Python and Running Your First Program", False, """
## Install Python

1. Go to **python.org** and download the latest Python 3 for your computer.
2. On Windows, tick **"Add python.exe to PATH"** before clicking *Install Now*.
3. Open *Command Prompt* and type `python --version` to check it worked.

## Your first program

Create a file named `hello.py` with this code:

```python
name = input("What is your name? ")
print("Welcome to Python,", name)
```

Run it from the folder where you saved it:

```bash
python hello.py
```

> **Tip:** If `python` does not work on Windows, try `py hello.py`.
"""),
    ("Basics", "Variables and Data Types", False, """
A **variable** is a name that stores a value.

```python
course = "Python for Beginners"   # str (text)
lessons = 24                      # int (whole number)
fee = 499.0                       # float (decimal)
is_free = False                   # bool (True/False)
```

## Checking the type

```python
print(type(lessons))   # <class 'int'>
```

## Converting between types

`input()` always gives text, so convert numbers before doing maths:

```python
age = int(input("Your age: "))
print("Next year you will be", age + 1)
```

## Practice

Write a program that asks for the price of a book and the quantity, then prints the total.
"""),
]

HTML_LESSONS = [
    ("Getting started", "What Is HTML?", True, """
**HTML (HyperText Markup Language)** describes the structure of every web page.

## Tags and elements

HTML uses **tags** in angle brackets:

```html
<h1>Welcome to my website</h1>
<p>This is a paragraph.</p>
```

- `<h1>` … `</h1>` is a **heading** element.
- `<p>` … `</p>` is a **paragraph** element.
- Most tags have an opening tag and a closing tag with a `/`.

> HTML gives a page its **structure**. CSS (a later course) gives it **style**.
"""),
    ("Getting started", "Your First Web Page", False, """
Every HTML5 page starts with the same skeleton:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>My First Page</title>
  </head>
  <body>
    <h1>Hello, world!</h1>
    <p>I am learning HTML5 with LearnInCreation.</p>
    <a href="https://learnincreation.com">Visit LearnInCreation</a>
  </body>
</html>
```

## Try it

1. Open Notepad (or VS Code) and paste the code.
2. Save the file as `index.html`.
3. Double-click the file to open it in your browser.

Change the heading text, save, and refresh the browser to see your change.
"""),
]

LESSONS = {
    "basics-of-computer-fundamentals": COMPUTER_LESSONS,
    "python-for-beginners": PYTHON_LESSONS,
    "introduction-to-html5": HTML_LESSONS,
}

# Study-center courses and fees as listed on learnincreation.com (2–3 month courses, 10 seats).
# title, linked online course slug, fee (₹)
BATCHES = [
    ("Fundamentals of Computer", "basics-of-computer-fundamentals", 2000),
    ("Networking Fundamentals", "networking-fundamentals", 2000),
    ("Proficiency in Microsoft Office", "proficiency-in-microsoft-office", 3000),
    ("Introduction to HTML5", "introduction-to-html5", 2500),
    ("Design with CSS3", "design-with-css3", 3000),
    ("Introduction to Web Designing", "introduction-to-web-designing", 4500),
    ("Web Development with Python", "web-development-with-python", 5000),
    ("Introduction to JavaScript", "introduction-to-javascript", 3000),
    ("Python for Beginners", "python-for-beginners", 3000),
    ("Introduction to Bootstrap", "introduction-to-bootstrap", 3000),
    ("Introduction to Digital Marketing", "introduction-to-digital-marketing", 5000),
    ("Facebook Marketing", "facebook-marketing", 5000),
]

BATCH_SLOTS = [("10:00", "12:00"), ("12:00", "14:00"), ("14:00", "16:00"), ("16:00", "18:00")]

# Sample library shifts (edit in the admin): name, start, end, monthly fee (₹)
SHIFTS = [
    ("Morning", "10:00", "14:00", 400),
    ("Evening", "14:00", "18:00", 400),
    ("Full day", "10:00", "18:00", 700),
]
