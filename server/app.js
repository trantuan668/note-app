const express = require("express");
const session = require("express-session");
const path = require("path");
const { sequelize } = require("./models");
const authRoutes = require("./routes/auth");
const noteRoutes = require("./routes/notes");

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "../public")));

app.use(session({
  secret: "note-secret",
  resave: false,
  saveUninitialized: false
}));

app.use("/api/auth", authRoutes);
app.use("/api/notes", noteRoutes);

app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "../public/index.html"));
});

sequelize.sync().then(() => {
  app.listen(3000, () => console.log("Server is running on http://localhost:3000"));
});