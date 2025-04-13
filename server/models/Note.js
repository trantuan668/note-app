const { DataTypes } = require("sequelize");
const { sequelize } = require("./index");
const User = require("./User");
const Note = sequelize.define("Note", {
  title: { type: DataTypes.STRING },
  content: { type: DataTypes.TEXT }
});
Note.belongsTo(User);
User.hasMany(Note);
module.exports = Note;