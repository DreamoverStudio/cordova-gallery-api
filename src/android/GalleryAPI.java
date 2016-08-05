package com.subitolabs.cordova.galleryapi;


import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import org.apache.cordova.*;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.Iterator;
import java.util.logging.Logger;

public class GalleryAPI extends CordovaPlugin {
    public static final String ACTION_GET_MEDIA = "getMedia";
    public static final String ACTION_GET_MEDIA_THUMBNAIL = "getMediaThumbnail";
    public static final String ACTION_GET_ALBUMS = "getAlbums";
    public static final String DIR_NAME = ".mendr";

    private static final int BASE_SIZE = 300;

    private static BitmapFactory.Options ops = null;

    @Override
    public boolean execute(String action, final JSONArray args, final CallbackContext callbackContext) throws JSONException {
        try {
            if (ACTION_GET_MEDIA.equals(action)) {
                cordova.getThreadPool().execute(new Runnable() {
                    public void run() {
                        try {
                            ArrayOfObjects albums = getMedia("" + args.get(0));
                            callbackContext.success(new JSONArray(albums));
                        } catch (Exception e) {
                            e.printStackTrace();
                            callbackContext.error(e.getMessage());
                        }
                    }
                });

                return true;
            } else if (ACTION_GET_MEDIA_THUMBNAIL.equals(action)) {
                cordova.getThreadPool().execute(new Runnable() {
                    public void run() {
                        try {
                            JSONObject media = getMediaThumbnail((JSONObject) args.get(0));
                            callbackContext.success(media);
                        } catch (Exception e) {
                            e.printStackTrace();
                            callbackContext.error(e.getMessage());
                        }
                    }
                });
                return true;
            } else if (ACTION_GET_ALBUMS.equals(action)) {
                cordova.getThreadPool().execute(new Runnable() {
                    public void run() {
                        try {
                            ArrayOfObjects albums = getBuckets();
                            callbackContext.success(new JSONArray(albums));
                        } catch (Exception e) {
                            e.printStackTrace();
                            callbackContext.error(e.getMessage());
                        }
                    }
                });

                return true;
            }
            callbackContext.error("Invalid action");
            return false;
        } catch (Exception e) {
            e.printStackTrace();
            callbackContext.error(e.getMessage());
            return false;
        }
    }

    public ArrayOfObjects getBuckets() throws JSONException {
        Object columns = new Object() {{
            put("id", MediaStore.Images.ImageColumns.BUCKET_ID);
            put("title", MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME);
        }};

        return queryContentProvider(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, columns, "1) GROUP BY 1,(2");
    }

    private ArrayOfObjects getMedia(String bucket) throws JSONException {
        Object columns = new Object() {{
            put("int.id", MediaStore.Images.Media._ID);
            put("data", MediaStore.MediaColumns.DATA);
            put("int.date_added", MediaStore.Images.ImageColumns.DATE_ADDED);
            put("title", MediaStore.Images.ImageColumns.DISPLAY_NAME);
            put("int.height", MediaStore.Images.ImageColumns.HEIGHT);
            put("int.width", MediaStore.Images.ImageColumns.WIDTH);
            put("int.orientation", MediaStore.Images.ImageColumns.ORIENTATION);
            put("mime_type", MediaStore.Images.ImageColumns.MIME_TYPE);
            put("float.lat", MediaStore.Images.ImageColumns.LATITUDE);
            put("float.lon", MediaStore.Images.ImageColumns.LONGITUDE);
            put("int.size", MediaStore.Images.ImageColumns.SIZE);
            put("int.thumbnail_id", MediaStore.Images.ImageColumns.MINI_THUMB_MAGIC);
        }};

        final ArrayOfObjects results = queryContentProvider(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, columns, "bucket_display_name = \"" + bucket + "\"");

        for (Object media : results) {
            File thumbnailPath = thumbnailPathFromMediaId(media.getString("id"));
            if (thumbnailPath.exists())
                media.put("thumbnail", thumbnailPath);
        }

        return results;
    }

    private JSONObject getMediaThumbnail(JSONObject media) throws JSONException {
        File thumbnailPath = thumbnailPathFromMediaId(media.getString("id"));
        if (thumbnailPath.exists())
        {
            System.out.println("Thumbnail Already Exists!!!. Not Creating New One");
            media.put("thumbnail", thumbnailPath);
        }
        else {
            if (ops == null)
            {
                ops = new BitmapFactory.Options();
                ops.inJustDecodeBounds = false;
                ops.inSampleSize = 8;
            }

            File image = new File(media.getString("data"));

            int sourceWidth = media.getInt("width");
            int sourceHeight = media.getInt("height");

            int destinationWidth, destinationHeight;

            if (sourceWidth > sourceHeight) {
                destinationHeight = BASE_SIZE;
                destinationWidth = (int) Math.ceil(destinationHeight * ((double) sourceWidth / sourceHeight));
            } else {
                destinationWidth = BASE_SIZE;
                destinationHeight = (int) Math.ceil(destinationWidth * ((double) sourceHeight / sourceWidth));
            }

//            System.out.println("before decoding: " + (double)(((new Date()).getTime()-beginDate.getTime())));

            Bitmap originalImageBitmap = BitmapFactory.decodeFile(image.getAbsolutePath(), ops); //creating bitmap of original image

//            System.out.println("before creating thubmnail: " + (double)(((new Date()).getTime()-beginDate.getTime())));

            Bitmap thumbnailBitmap = Bitmap.createScaledBitmap(originalImageBitmap, destinationWidth, destinationHeight, true);
            originalImageBitmap.recycle();

//            System.out.println("after creating thubmnail: " + (double)(((new Date()).getTime()-beginDate.getTime())));

            int orientation = media.getInt("orientation");
            if (orientation > 0)
                thumbnailBitmap = rotate(thumbnailBitmap, orientation);

            byte[] thumbnailData = getBytesFromBitmap(thumbnailBitmap);
            thumbnailBitmap.recycle();
//            System.out.println("after rotating thubmnail: " + (double)(((new Date()).getTime()-beginDate.getTime())));

            FileOutputStream outStream;
            try {
                outStream = new FileOutputStream(thumbnailPath);
                outStream.write(thumbnailData);
                outStream.close();
            } catch (IOException e) {
                e.printStackTrace();
            }

            if (thumbnailPath.exists())
            {
                System.out.println("Thumbnail didn't Exists!!!. Created New One");
                media.put("thumbnail", thumbnailPath);
            }
        }

        return media;
    }

    private byte[] getBytesFromBitmap(Bitmap bitmap) {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream);
        return stream.toByteArray();
    }

    private static Bitmap rotate(Bitmap source, int orientation) {
        Matrix matrix = new Matrix();
        matrix.postRotate((float) orientation);
        return Bitmap.createBitmap(source, 0, 0, source.getWidth(), source.getHeight(), matrix, false);
    }

    private File thumbnailPathFromMediaId(String mediaId) {
        File thumbnailPath = null;

        String thumbnailName = mediaId + "_mthumb.png";
        File dir = new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), DIR_NAME);
        if (!dir.exists()) {
            if (!dir.mkdirs()) {
                Log.e("Mendr", "Failed to create storage directory.");
                return thumbnailPath;
            }
        }

        thumbnailPath = new File(dir.getPath() + File.separator + thumbnailName);

        return thumbnailPath;
    }

    private Context getContext() {
        return this.cordova.getActivity().getApplicationContext();
    }

    private ArrayOfObjects queryContentProvider(Uri collection, Object columns, String whereClause) throws JSONException {
        final ArrayList<String> columnNames = new ArrayList<String>();
        final ArrayList<String> columnValues = new ArrayList<String>();

        Iterator<String> iteratorFields = columns.keys();

        while (iteratorFields.hasNext()) {
            String column = iteratorFields.next();

            columnNames.add(column);
            columnValues.add("" + columns.getString(column));
        }

        final Cursor cursor = getContext().getContentResolver().query(collection, columnValues.toArray(new String[columns.length()]), whereClause, null, null);
        final ArrayOfObjects buffer = new ArrayOfObjects();

        if (cursor.moveToFirst()) {
            do {
                Object item = new Object();

                for (String column : columnNames) {
                    int columnIndex = cursor.getColumnIndex(columns.get(column).toString());

                    if (column.startsWith("int.")) {
                        item.put(column.substring(4), cursor.getInt(columnIndex));
                    } else if (column.startsWith("float.")) {
                        item.put(column.substring(6), cursor.getFloat(columnIndex));
                    } else {
                        item.put(column, cursor.getString(columnIndex));
                    }
                }

                buffer.add(item);
            }
            while (cursor.moveToNext());
        }

        cursor.close();

        return buffer;
    }

    private class Object extends JSONObject {

    }

    private class ArrayOfObjects extends ArrayList<Object> {

    }
}

/*
*
*
* {
                int sourceWidth = media.getInt("width");
                int sourceHeight = media.getInt("height");

                int destinationWidth,destinationHeight;

                if (sourceWidth > sourceHeight)
                {
                    destinationHeight = BASE_SIZE;
                    destinationWidth = (int) Math.ceil(destinationHeight * ((double)sourceWidth/sourceHeight));
                } else {
                    destinationWidth = BASE_SIZE;
                    destinationHeight = (int) Math.ceil(destinationWidth * ((double)sourceHeight/sourceWidth));
                }

                System.out.println("before decoding: " + (double)(((new Date()).getTime()-beginDate.getTime())));

                Bitmap originalImageBitmap = BitmapFactory.decodeFile(image.getAbsolutePath(), ops); //creating bitmap of original image

                System.out.println("before creating thubmnail: " + (double)(((new Date()).getTime()-beginDate.getTime())));

                Bitmap thumbnailBitmap = Bitmap.createScaledBitmap(originalImageBitmap, destinationWidth, destinationHeight, true);

                System.out.println("after creating thubmnail: " + (double)(((new Date()).getTime()-beginDate.getTime())));

                int orientation = media.getInt("orientation");
                if (orientation > 0)
                {
                    thumbnailBitmap = rotate(thumbnailBitmap, orientation);
                }

                byte[] thumbnailData = getBytesFromBitmap(thumbnailBitmap);

                System.out.println("after rotating thubmnail: " + (double)(((new Date()).getTime()-beginDate.getTime())));

                FileOutputStream outStream;
                try {
                    outStream = new FileOutputStream(thumbnailPath);
                    outStream.write(thumbnailData);
                    outStream.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
*
* {
            File image = new File(media.getString("data"));
            String originalImageName = image.getName();
            int pos = originalImageName.lastIndexOf(".");
            if (pos > 0)
                originalImageName = originalImageName.substring(0, pos);

            String thumbnailName = originalImageName + "_mthumb.png";
            File dir = new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ".mendr");
            if (!dir.exists()) {
                if (!dir.mkdirs()) {
                    Log.e("Mendr", "Failed to create storage directory.");
                }
            }

            File thumbnailPath = new File(dir.getPath() + File.separator + thumbnailName);

            if (thumbnailPath.exists())
                media.put("thumbnail", thumbnailPath);
        }
*
* */
