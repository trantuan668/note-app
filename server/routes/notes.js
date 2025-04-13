const express = require("express");
const Note = require("../models/Note");
const auth = require("../middleware/authMiddleware");
const router = express.Router();

router.get("/", auth, async (req, res) => {
  const notes = await Note.findAll({ where: { UserId: req.session.userId } });
  res.json(notes);
});

router.post("/", auth, async (req, res) => {
  const note = await Note.create({
    title: req.body.title,
    content: req.body.content,
    UserId: req.session.userId
  });
  res.json(note);
});

router.put("/:id", auth, async (req, res) => {
  const note = await Note.findOne({ where: { id: req.params.id, UserId: req.session.userId } });
  if (note) {
    note.title = req.body.title;
    note.content = req.body.content;
    await note.save();
    res.json(note);
  } else {
    res.status(404).json({ error: "Note not found" });
  }
});

router.delete("/:id", auth, async (req, res) => {
  const deleted = await Note.destroy({ where: { id: req.params.id, UserId: req.session.userId } });
  res.json({ deleted });
});

module.exports = router;