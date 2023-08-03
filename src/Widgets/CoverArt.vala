/*
 * SPDX-License-Identifier: LGPL-3.0.or-later
 * SPDX-FileCopyrightText: 2021 Christopher Leggett <chris@leggett.dev>
 */

namespace Leopod {
    public class CoverArt : Gtk.Box {
        public Podcast podcast { get; construct; }
        public bool title_visible { get; construct; }

        public CoverArt (Podcast podcast, bool title_visible = true) {
            Object (podcast: podcast, title_visible: title_visible);
        }

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            var controller = new Gtk.GestureClick ();
            controller.released.connect ((num_presses, x, y) => {
                    clicked (this.podcast);
                    });
            add_controller (controller);
            Gtk.Image image = new Gtk.Image () {
                margin_top = margin_end = margin_start = margin_bottom = 2,
            };
            Gtk.Button button = new Gtk.Button () {
                tooltip_text = _("Browse Podcast Episodes"),
            };
            button.get_style_context ().add_class ("coverart");

            //Load the actual coverart
            info (podcast.local_art_uri);
            var file = GLib.File.new_for_uri (podcast.local_art_uri);
            if (!file.query_exists ()) {
                cache_album_art (podcast);
                info (podcast.local_art_uri);
                file = GLib.File.new_for_uri (podcast.local_art_uri);
            }
            image.set_from_file (file.get_path ());
            image.pixel_size = 170;
            image.show ();
            show ();

            append (image);
            if (title_visible) {
                Granite.HeaderLabel name = new Granite.HeaderLabel (podcast.name) {
                    halign = Gtk.Align.CENTER,
                };
                append (name);
            }
        }

        public signal void clicked (Podcast podcast);
    }

    /*
     * Downloads and Caches a podcast's album art if it doesn't
     * already exist.
     */
     private void cache_album_art (Podcast podcast) {
        // Set the local library directory and replace ~ with absolute path
        string local_library_path = GLib.Environment.get_user_data_dir () + """/leopod""";
        local_library_path = local_library_path.replace (
            "~",
            GLib.Environment.get_home_dir ()
        );
        try {
            podcast.cache_album_art (local_library_path);
        } catch (Error e) {
            error ("unable to save a local copy of album art. %s", e.message);
        }
    }

}
