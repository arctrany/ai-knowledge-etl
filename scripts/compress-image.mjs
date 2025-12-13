#!/usr/bin/env node
/**
 * Cross-platform image compression script
 * Resizes images to max width for AI processing
 *
 * Usage:
 *   Single file: node compress-image.mjs <input> <output> [maxWidth]
 *   Batch mode:  node compress-image.mjs --batch <inputDir> <outputDir> [maxWidth]
 *
 * Examples:
 *   node compress-image.mjs screenshot.png compressed.jpg 1280
 *   node compress-image.mjs --batch ./images ./compressed 1280
 *
 * Dependencies: sharp (installed via npm dynamically if needed)
 */

import { existsSync, mkdirSync, readdirSync, statSync } from 'fs';
import { dirname, resolve, extname, basename, join } from 'path';

const args = process.argv.slice(2);
const isBatch = args[0] === '--batch';

if (args.length < 2 || (isBatch && args.length < 3)) {
  console.error('Usage:');
  console.error('  Single file: node compress-image.mjs <input> <output> [maxWidth]');
  console.error('  Batch mode:  node compress-image.mjs --batch <inputDir> <outputDir> [maxWidth]');
  console.error('');
  console.error('Options:');
  console.error('  maxWidth: Maximum width in pixels (default: 1280)');
  process.exit(1);
}

async function getSharp() {
  try {
    return (await import('sharp')).default;
  } catch (e) {
    console.error('sharp module not found. Installing...');
    const { execSync } = await import('child_process');
    try {
      execSync('npm install sharp --no-save', { stdio: 'inherit' });
      return (await import('sharp')).default;
    } catch (installError) {
      console.error('Failed to install sharp. Please run: npm install sharp');
      process.exit(1);
    }
  }
}

async function compressImage(sharp, inputPath, outputPath, maxWidth) {
  if (!existsSync(inputPath)) {
    console.error(`Error: Input file not found: ${inputPath}`);
    return false;
  }

  // Ensure output directory exists
  const outputDir = dirname(outputPath);
  if (!existsSync(outputDir)) {
    mkdirSync(outputDir, { recursive: true });
  }

  try {
    const image = sharp(inputPath);
    const metadata = await image.metadata();

    const originalSize = statSync(inputPath).size;
    const originalDims = `${metadata.width}x${metadata.height}`;

    let result;
    if (metadata.width > maxWidth) {
      result = await image
        .resize(maxWidth, null, {
          withoutEnlargement: true,
          fit: 'inside'
        })
        .jpeg({ quality: 85 })
        .toFile(outputPath);
    } else {
      // Just convert to JPEG for consistent format
      result = await image.jpeg({ quality: 90 }).toFile(outputPath);
    }

    const compressedSize = statSync(outputPath).size;
    const reduction = ((1 - compressedSize / originalSize) * 100).toFixed(1);

    console.log(`✓ ${basename(inputPath)}`);
    console.log(`  Original: ${originalDims} (${formatBytes(originalSize)})`);
    console.log(`  Compressed: ${result.width}x${result.height} (${formatBytes(compressedSize)})`);
    console.log(`  Reduction: ${reduction}%`);
    console.log(`  Output: ${outputPath}`);
    console.log('');

    return true;
  } catch (error) {
    console.error(`✗ ${basename(inputPath)}: ${error.message}`);
    return false;
  }
}

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function isImageFile(filename) {
  const ext = extname(filename).toLowerCase();
  return ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.tiff'].includes(ext);
}

async function main() {
  const sharp = await getSharp();

  if (isBatch) {
    // Batch mode
    const inputDir = resolve(args[1]);
    const outputDir = resolve(args[2]);
    const maxWidth = parseInt(args[3] || '1280', 10);

    if (!existsSync(inputDir)) {
      console.error(`Error: Input directory not found: ${inputDir}`);
      process.exit(1);
    }

    if (!existsSync(outputDir)) {
      mkdirSync(outputDir, { recursive: true });
    }

    console.log(`Batch compression: ${inputDir} → ${outputDir}`);
    console.log(`Max width: ${maxWidth}px`);
    console.log('');

    const files = readdirSync(inputDir).filter(isImageFile);

    if (files.length === 0) {
      console.log('No image files found in input directory.');
      process.exit(0);
    }

    let success = 0;
    let failed = 0;

    for (const file of files) {
      const inputPath = join(inputDir, file);
      const outputName = basename(file, extname(file)) + '.jpg';
      const outputPath = join(outputDir, outputName);

      if (await compressImage(sharp, inputPath, outputPath, maxWidth)) {
        success++;
      } else {
        failed++;
      }
    }

    console.log('─'.repeat(40));
    console.log(`Completed: ${success} success, ${failed} failed`);

  } else {
    // Single file mode
    const inputPath = resolve(args[0]);
    const outputPath = resolve(args[1]);
    const maxWidth = parseInt(args[2] || '1280', 10);

    console.log(`Compressing: ${inputPath}`);
    console.log(`Max width: ${maxWidth}px`);
    console.log('');

    const success = await compressImage(sharp, inputPath, outputPath, maxWidth);
    process.exit(success ? 0 : 1);
  }
}

main();
